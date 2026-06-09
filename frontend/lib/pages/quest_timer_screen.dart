import 'dart:async';

import 'package:circular_countdown_timer/circular_countdown_timer.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:start_on/pages/add_quest_screen.dart';
import 'package:start_on/models/app_local_data.dart';
import 'package:start_on/pages/quest_timer/quest_timer_sections.dart';
import 'package:start_on/services/quest_timer_background_service.dart';
import 'package:start_on/storage/quest_image_store.dart';
import 'package:start_on/widgets/ai_quest_creation_progress_overlay.dart';

typedef QuestAiSuggestionRequestHandler =
    Future<QuestItem?> Function({
      required QuestItem originalQuest,
      required QuestItem draft,
      ValueChanged<bool>? onCreationLoadingChanged,
    });

class QuestTimerScreen extends StatefulWidget {
  const QuestTimerScreen({
    super.key,
    required this.quest,
    required this.notificationsEnabled,
    this.autoStartOnOpen = false,
    this.onQuestChanged,
    this.onAiSuggestionRequested,
  });

  final QuestItem quest;
  final bool notificationsEnabled;
  final bool autoStartOnOpen;
  final ValueChanged<QuestItem>? onQuestChanged;
  final QuestAiSuggestionRequestHandler? onAiSuggestionRequested;

  @override
  State<QuestTimerScreen> createState() => _QuestTimerScreenState();
}

class QuestTimerScreenResult {
  const QuestTimerScreenResult({
    required this.quest,
    required this.didPauseTimer,
  });

  final QuestItem quest;
  final bool didPauseTimer;
}

class QuestTimerDeleteResult {
  const QuestTimerDeleteResult(this.quest);

  final QuestItem quest;
}

class _QuestTimerScreenState extends State<QuestTimerScreen> {
  // 타이머 제어, 이미지 선택, 인증 이미지 저장을 담당하는 객체들.
  final CountDownController _countDownController = CountDownController();
  final ImagePicker _imagePicker = ImagePicker();
  final QuestImageStore _questImageStore = const QuestImageStore();

  // 화면에서 직접 관리하는 진행 상태.
  final QuestTimerBackgroundService _questTimerService =
      QuestTimerBackgroundService.instance;

  Timer? _localTicker;
  StreamSubscription<QuestTimerSnapshot>? _questTimerTickSubscription;
  late QuestItem _quest;
  XFile? _proofImage;
  int _elapsedSeconds = 0;
  int _timerViewRevision = 0;
  bool _hasStarted = false;
  bool _running = false;
  bool _isCompleting = false;
  bool _isGeneratingAiSuggestion = false;

  @override
  void initState() {
    super.initState();
    _quest = _normalizeQuestProgress(widget.quest);
    _elapsedSeconds = _clampElapsedSeconds(
      _quest.elapsedSeconds,
      _durationSeconds,
    );
    if (widget.notificationsEnabled) {
      _listenToBackgroundTimer();
    }
    if (widget.autoStartOnOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _running || _hasStarted || _isCompleting) {
          return;
        }
        _toggleTimer();
      });
    }
  }

  @override
  void dispose() {
    _localTicker?.cancel();
    _questTimerTickSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxDurationSeconds = _durationSeconds;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        _popWithProgress();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F3F8),
        body: Stack(
          children: [
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final useLandscapeLayout =
                      constraints.maxWidth > constraints.maxHeight &&
                      constraints.maxWidth >= 640;

                  final content = QuestTimerContentCard(
                    useLandscapeLayout: useLandscapeLayout,
                    header: QuestTimerHeader(
                      onBack: _popWithProgress,
                      onEdit: _editQuest,
                    ),
                    questSummary: QuestTimerSummary(
                      quest: _quest,
                      earnedExp: _calculateEarnedExp(),
                      maxDurationSeconds: maxDurationSeconds,
                      onSubtaskSelect: _selectSubtask,
                      onAddSubtaskTime: _addSubtaskTime,
                    ),
                    countdown: QuestTimerCountdown(
                      controller: _countDownController,
                      durationSeconds: maxDurationSeconds,
                      elapsedSeconds: _elapsedSeconds,
                      timerViewRevision: _timerViewRevision,
                      running: _running,
                      onComplete: _handleTimerComplete,
                      onToggleTimer: _toggleTimer,
                      formatDuration: _formatDuration,
                    ),
                    actionButtons: QuestTimerActionButtons(
                      isCompleting: _isCompleting,
                      running: _running,
                      canReset: _elapsedSeconds > 0,
                      canComplete: _elapsedSeconds >= 60,
                      onResetTimer: _resetTimer,
                      onToggleTimer: _toggleTimer,
                      onStopTimer: _completeQuest,
                    ),
                    proofSection: QuestTimerProofSection(
                      proofImagePath: _proofImage?.path,
                      isCompleting: _isCompleting,
                      compact: useLandscapeLayout,
                      onPickCamera: () => _pickProofImage(ImageSource.camera),
                      onPickGallery: () => _pickProofImage(ImageSource.gallery),
                      onClearImage: () => setState(() => _proofImage = null),
                    ),
                    categoryTimes: QuestTimerCategoryTimes(
                      category: _quest.category,
                      elapsedSeconds: _elapsedSeconds,
                      compact: useLandscapeLayout,
                      formatDuration: _formatDuration,
                    ),
                  );

                  if (useLandscapeLayout) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(30, 20, 30, 32),
                      child: content,
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
                    children: [content],
                  );
                },
              ),
            ),
            if (_isGeneratingAiSuggestion)
              const AiQuestCreationProgressOverlay(),
          ],
        ),
      ),
    );
  }

  void _handleTimerComplete() {
    // 계획 시간이 끝나도 완료 처리하지 않고, 로컬 ticker로 초과 시간을 계속 기록한다.
  }

  void _toggleTimer() {
    unawaited(_toggleTimerAsync());
  }

  void _resetTimer() {
    unawaited(_resetTimerAsync());
  }

  int get _durationSeconds {
    final durationSeconds = _quest.effectiveDurationSeconds;
    if (durationSeconds <= 0) {
      return 1;
    }
    return durationSeconds;
  }

  void _selectSubtask(String subtaskId) {
    final canSelect = _quest.subtasks.any(
      (subtask) => subtask.id == subtaskId && !subtask.isDone,
    );
    if (!canSelect) {
      return;
    }

    final updatedQuest = _quest.copyWith(
      elapsedSeconds: _elapsedSeconds,
      activeSubtaskId: subtaskId,
    );

    setState(() => _quest = updatedQuest);
    widget.onQuestChanged?.call(updatedQuest);
  }

  void _addSubtaskTime(String subtaskId) {
    final subtasks = _quest.subtasks.map((subtask) {
      if (subtask.id != subtaskId) {
        return subtask;
      }
      final currentMinutes = subtask.estimatedMinutes;
      final nextMinutes = (currentMinutes == null || currentMinutes <= 0)
          ? 11
          : currentMinutes + 10;
      return subtask.copyWith(
        estimatedMinutes: nextMinutes,
        status: subtask.isDone ? 'todo' : subtask.status,
        completedAt: subtask.isDone ? null : subtask.completedAt,
      );
    }).toList();

    final updatedQuest = _quest.copyWith(
      subtasks: subtasks,
      activeSubtaskId: _validActiveSubtaskId(subtasks, _quest.activeSubtaskId),
    );
    setState(() {
      _quest = updatedQuest;
      _timerViewRevision += 1;
    });
    widget.onQuestChanged?.call(updatedQuest);
  }

  Future<void> _toggleTimerAsync() async {
    // 진행 중이면 일시정지, 끝까지 찼으면 초기화 후 재시작, 그 외에는 시작/재개.
    if (_running) {
      if (_elapsedSeconds < _durationSeconds) {
        _countDownController.pause();
      }
      _stopLocalTicker();
      if (mounted) {
        setState(() => _running = false);
      }
      if (widget.notificationsEnabled) {
        await _questTimerService.pauseTimer(
          questId: _quest.id,
          questTitle: _quest.title,
          elapsedSeconds: _elapsedSeconds,
          defaultDurationSeconds: _durationSeconds,
        );
      }
      return;
    }

    if (_hasStarted) {
      _countDownController.resume();
    } else {
      _countDownController.start();
      _hasStarted = true;
    }

    setState(() => _running = true);
    _startLocalTicker();

    if (widget.notificationsEnabled) {
      await _questTimerService.startOrResumeTimer(
        questId: _quest.id,
        questTitle: _quest.title,
        elapsedSeconds: _elapsedSeconds,
        defaultDurationSeconds: _durationSeconds,
      );
    }
  }

  Future<void> _resetTimerAsync() async {
    final resetTarget = await _pickResetTarget();
    if (!mounted || resetTarget == null) {
      return;
    }

    if (_running) {
      _countDownController.pause();
    }

    _stopLocalTicker();

    if (widget.notificationsEnabled) {
      await _questTimerService.stopTimer();
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _applyResetTarget(resetTarget);
      _hasStarted = false;
      _running = false;
      _timerViewRevision += 1;
    });
    widget.onQuestChanged?.call(_quest);
  }

  Future<_TimerResetTarget?> _pickResetTarget() async {
    if (_quest.subtasks.isEmpty) {
      return const _TimerResetTarget.all();
    }

    return showModalBottomSheet<_TimerResetTarget>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F3F8),
              borderRadius: BorderRadius.circular(26),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.14),
                  blurRadius: 32,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '시간 초기화',
                  style: TextStyle(
                    color: Color(0xFF172033),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.restart_alt_rounded),
                  title: const Text('해당 퀘스트 전체 시간 초기화'),
                  onTap: () => Navigator.of(context).pop(const _TimerResetTarget.all()),
                ),
                const Divider(height: 12),
                for (final subtask in _quest.subtasks)
                  ListTile(
                    leading: const Icon(Icons.timer_outlined),
                    title: Text(subtask.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${_formatDuration(Duration(seconds: subtask.clampedElapsedSeconds))} / '
                      '${_formatDuration(Duration(seconds: subtask.plannedDurationSeconds))}',
                    ),
                    onTap: () => Navigator.of(context).pop(
                      _TimerResetTarget.subtask(subtask.id),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _applyResetTarget(_TimerResetTarget target) {
    if (target.subtaskId == null) {
      final resetSubtasks = _resetSubtasks(_quest.subtasks);
      _elapsedSeconds = 0;
      _quest = _quest.copyWith(
        elapsedSeconds: 0,
        subtasks: resetSubtasks,
        activeSubtaskId: _firstIncompleteSubtaskId(resetSubtasks),
      );
      return;
    }

    final subtasks = _quest.subtasks.map((subtask) {
      if (subtask.id != target.subtaskId) {
        return subtask;
      }
      _elapsedSeconds = (_elapsedSeconds - subtask.clampedElapsedSeconds)
          .clamp(0, 1 << 31)
          .toInt();
      return subtask.copyWith(status: 'todo', completedAt: null, elapsedSeconds: 0);
    }).toList();
    _quest = _quest.copyWith(
      elapsedSeconds: _elapsedSeconds,
      subtasks: subtasks,
      activeSubtaskId: target.subtaskId,
    );
  }

  Future<void> _editQuest() async {
    final result = await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (context) => AddQuestScreen(
          initialQuest: _quest.copyWith(elapsedSeconds: _elapsedSeconds),
          title: '퀘스트 수정',
          submitLabel: '적용',
          showDeleteAction: true,
          returnAiSuggestionRequest: true,
        ),
      ),
    );

    if (!mounted || result == null) {
      return;
    }

    if (result == AddQuestScreenResult.deleteQuest) {
      Navigator.of(context).pop(QuestTimerDeleteResult(_quest));
      return;
    }

    if (result case AddQuestScreenAiSuggestionRequest request) {
      final suggestionHandler = widget.onAiSuggestionRequested;
      if (suggestionHandler == null) {
        return;
      }

      final QuestItem? suggestedQuest;
      try {
        suggestedQuest = await suggestionHandler(
          originalQuest: _quest.copyWith(elapsedSeconds: _elapsedSeconds),
          draft: request.draft.copyWith(elapsedSeconds: _elapsedSeconds),
          onCreationLoadingChanged: _setAiSuggestionLoading,
        );
      } finally {
        _setAiSuggestionLoading(false);
      }
      if (!mounted || suggestedQuest == null) {
        return;
      }

      await _applyEditedQuest(suggestedQuest);
      return;
    }

    if (result is! QuestItem) {
      return;
    }

    await _applyEditedQuest(result);
  }

  void _setAiSuggestionLoading(bool isLoading) {
    if (!mounted || _isGeneratingAiSuggestion == isLoading) {
      return;
    }

    setState(() => _isGeneratingAiSuggestion = isLoading);
  }

  Future<void> _applyEditedQuest(QuestItem updatedQuest) async {
    final questWithProgress = _normalizeQuestProgress(
      updatedQuest.copyWith(elapsedSeconds: _elapsedSeconds),
    );

    setState(() {
      _quest = questWithProgress;
      _timerViewRevision += 1;
    });

    if (_running && widget.notificationsEnabled) {
      await _questTimerService.startOrResumeTimer(
        questId: _quest.id,
        questTitle: _quest.title,
        elapsedSeconds: _elapsedSeconds,
        defaultDurationSeconds: _durationSeconds,
      );
    }

    if (_running && _elapsedSeconds < _durationSeconds) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _countDownController.start();
      });
    }

    widget.onQuestChanged?.call(_quest);
  }

  Future<void> _pickProofImage(ImageSource source) async {
    final image = await _imagePicker.pickImage(
      source: source,
      imageQuality: 88,
      maxWidth: 1800,
    );

    if (image == null || !mounted) {
      return;
    }

    setState(() => _proofImage = image);
  }

  Future<void> _completeQuest() async {
    // 완료 시 현재 경과 시간과 인증 사진 경로를 기록 화면으로 전달한다.
    if (!mounted || _isCompleting) {
      return;
    }
    if (_elapsedSeconds < 60) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('퀘스트 완료는 1분 뒤부터 가능해요.')),
      );
      return;
    }

    setState(() => _isCompleting = true);

    if (_running) {
      _stopLocalTicker();
      if (widget.notificationsEnabled) {
        await _questTimerService.stopTimer();
      }
      if (!mounted) {
        return;
      }
      setState(() => _running = false);
    } else if (widget.notificationsEnabled) {
      await _questTimerService.stopTimer();
    }

    final completedAt = DateTime.now();
    String? proofImagePath;
    if (_proofImage != null) {
      proofImagePath = await _questImageStore.savePickedImage(
        _proofImage!,
        questId: _quest.id,
        completedAt: completedAt,
      );
    }

    if (!mounted) {
      return;
    }

    final earnedExp = _calculateEarnedExp();

    Navigator.of(context).pop(
      CompletedQuestRecord(
        questId: _quest.id,
        title: _quest.title,
        difficulty: _quest.difficulty,
        category: _quest.category,
        earnedExp: earnedExp,
        completedAt: completedAt.toIso8601String(),
        elapsedSeconds: _elapsedSeconds,
        subtasks: _quest.subtasks,
        proofImagePath: proofImagePath,
        syncTarget: _quest.syncTarget,
      ),
    );
  }

  int _calculateEarnedExp() {
    return _quest.exp;
  }

  void _popWithProgress() {
    unawaited(_popWithProgressAsync());
  }

  Future<void> _popWithProgressAsync() async {
    var didPauseTimer = false;

    if (_running) {
      if (_elapsedSeconds < _durationSeconds) {
        _countDownController.pause();
      }
      _stopLocalTicker();
      if (widget.notificationsEnabled) {
        await _questTimerService.pauseTimer(
          questId: _quest.id,
          questTitle: _quest.title,
          elapsedSeconds: _elapsedSeconds,
          defaultDurationSeconds: _durationSeconds,
        );
      }
      if (!mounted) {
        return;
      }
      setState(() => _running = false);
      didPauseTimer = true;
    }

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(
      QuestTimerScreenResult(
        quest: _quest.copyWith(elapsedSeconds: _elapsedSeconds),
        didPauseTimer: didPauseTimer,
      ),
    );
  }

  void _startLocalTicker() {
    _localTicker?.cancel();
    _localTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_running || _isCompleting) {
        return;
      }

      _advanceQuestProgress(1);
    });
  }

  bool _advanceQuestProgress(
    int elapsedDeltaSeconds, {
    bool? running,
    bool? hasStarted,
  }) {
    if (elapsedDeltaSeconds <= 0) {
      return false;
    }

    if (_quest.subtasks.isEmpty) {
      final nextElapsedSeconds = _nonNegativeElapsedSeconds(
        _elapsedSeconds + elapsedDeltaSeconds,
      );
      final updatedQuest = _quest.copyWith(elapsedSeconds: nextElapsedSeconds);
      setState(() {
        _elapsedSeconds = nextElapsedSeconds;
        _quest = updatedQuest;
        if (running != null) {
          _running = running;
        }
        if (hasStarted != null) {
          _hasStarted = hasStarted;
        }
      });
      widget.onQuestChanged?.call(updatedQuest);
      return false;
    }

    final result = _advanceSubtasks(
      _quest.subtasks,
      activeSubtaskId: _quest.effectiveActiveSubtaskId,
      elapsedDeltaSeconds: elapsedDeltaSeconds,
      completedAt: DateTime.now(),
    );
    final nextElapsedSeconds = _nonNegativeElapsedSeconds(
      _elapsedSeconds + elapsedDeltaSeconds,
    );
    final updatedQuest = _quest.copyWith(
      elapsedSeconds: nextElapsedSeconds,
      subtasks: result.subtasks,
      activeSubtaskId: result.activeSubtaskId,
    );

    setState(() {
      _elapsedSeconds = nextElapsedSeconds;
      _quest = updatedQuest;
      if (running != null) {
        _running = running;
      }
      if (hasStarted != null) {
        _hasStarted = hasStarted;
      }
    });
    widget.onQuestChanged?.call(updatedQuest);

    return false;
  }

  QuestItem _normalizeQuestProgress(QuestItem quest) {
    if (quest.subtasks.isEmpty) {
      return quest.copyWith(
        elapsedSeconds: _nonNegativeElapsedSeconds(quest.elapsedSeconds),
        activeSubtaskId: null,
      );
    }

    final normalizedSubtasks = _normalizeSubtasks(quest.subtasks);
    final trackedSubtaskSeconds = _sumSubtaskElapsedSeconds(normalizedSubtasks);
    final elapsedGap = quest.elapsedSeconds - trackedSubtaskSeconds;
    final activeSubtaskId = _validActiveSubtaskId(
      normalizedSubtasks,
      quest.activeSubtaskId,
    );

    if (elapsedGap <= 0) {
      return quest.copyWith(
        elapsedSeconds: _nonNegativeElapsedSeconds(quest.elapsedSeconds),
        subtasks: normalizedSubtasks,
        activeSubtaskId: activeSubtaskId,
      );
    }

    final advanced = _advanceSubtasks(
      normalizedSubtasks,
      activeSubtaskId: activeSubtaskId,
      elapsedDeltaSeconds: elapsedGap,
      completedAt: DateTime.now(),
    );

    return quest.copyWith(
      elapsedSeconds: _nonNegativeElapsedSeconds(quest.elapsedSeconds),
      subtasks: advanced.subtasks,
      activeSubtaskId: advanced.activeSubtaskId,
    );
  }

  List<QuestSubtask> _normalizeSubtasks(List<QuestSubtask> subtasks) {
    return subtasks.map((subtask) {
      final plannedDurationSeconds = subtask.plannedDurationSeconds;
      final elapsedSeconds = _clampElapsedSeconds(
        subtask.elapsedSeconds,
        plannedDurationSeconds,
      );
      if (subtask.isDone) {
        return subtask.copyWith(elapsedSeconds: plannedDurationSeconds);
      }
      if (elapsedSeconds >= plannedDurationSeconds) {
        return subtask.copyWith(
          status: 'done',
          completedAt: subtask.completedAt ?? DateTime.now(),
          elapsedSeconds: plannedDurationSeconds,
        );
      }
      return subtask.copyWith(elapsedSeconds: elapsedSeconds);
    }).toList();
  }

  List<QuestSubtask> _resetSubtasks(List<QuestSubtask> subtasks) {
    return subtasks
        .map(
          (subtask) => subtask.copyWith(
            status: 'todo',
            completedAt: null,
            elapsedSeconds: 0,
          ),
        )
        .toList();
  }

  _SubtaskAdvanceResult _advanceSubtasks(
    List<QuestSubtask> sourceSubtasks, {
    required String? activeSubtaskId,
    required int elapsedDeltaSeconds,
    required DateTime completedAt,
  }) {
    final subtasks = _normalizeSubtasks(sourceSubtasks);
    var remainingSeconds = elapsedDeltaSeconds;
    var appliedSeconds = 0;
    var currentActiveSubtaskId = _validActiveSubtaskId(
      subtasks,
      activeSubtaskId,
    );

    while (remainingSeconds > 0 && currentActiveSubtaskId != null) {
      final activeIndex = _subtaskIndexById(subtasks, currentActiveSubtaskId);
      if (activeIndex < 0) {
        currentActiveSubtaskId = _firstIncompleteSubtaskId(subtasks);
        continue;
      }

      final activeSubtask = subtasks[activeIndex];
      final plannedDurationSeconds = activeSubtask.plannedDurationSeconds;
      final currentElapsedSeconds = _clampElapsedSeconds(
        activeSubtask.elapsedSeconds,
        plannedDurationSeconds,
      );
      final remainingForSubtask =
          plannedDurationSeconds - currentElapsedSeconds;

      if (remainingForSubtask <= 0) {
        subtasks[activeIndex] = activeSubtask.copyWith(
          status: 'done',
          completedAt: activeSubtask.completedAt ?? completedAt,
          elapsedSeconds: plannedDurationSeconds,
        );
        currentActiveSubtaskId = _firstIncompleteSubtaskId(subtasks);
        continue;
      }

      final secondsForSubtask = remainingSeconds < remainingForSubtask
          ? remainingSeconds
          : remainingForSubtask;
      final nextElapsedSeconds = currentElapsedSeconds + secondsForSubtask;
      final isSubtaskDone = nextElapsedSeconds >= plannedDurationSeconds;

      appliedSeconds += secondsForSubtask;
      remainingSeconds -= secondsForSubtask;
      subtasks[activeIndex] = activeSubtask.copyWith(
        status: isSubtaskDone ? 'done' : activeSubtask.status,
        completedAt: isSubtaskDone
            ? activeSubtask.completedAt ?? completedAt
            : activeSubtask.completedAt,
        elapsedSeconds: nextElapsedSeconds,
      );

      currentActiveSubtaskId = isSubtaskDone
          ? _firstIncompleteSubtaskId(subtasks)
          : activeSubtask.id;
    }

    return _SubtaskAdvanceResult(
      subtasks: subtasks,
      activeSubtaskId: currentActiveSubtaskId,
      appliedSeconds: appliedSeconds,
    );
  }

  String? _validActiveSubtaskId(
    List<QuestSubtask> subtasks,
    String? activeSubtaskId,
  ) {
    if (activeSubtaskId != null) {
      for (final subtask in subtasks) {
        if (subtask.id == activeSubtaskId && !subtask.isDone) {
          return subtask.id;
        }
      }
    }
    return _firstIncompleteSubtaskId(subtasks);
  }

  String? _firstIncompleteSubtaskId(List<QuestSubtask> subtasks) {
    for (final subtask in subtasks) {
      if (!subtask.isDone) {
        return subtask.id;
      }
    }
    return null;
  }

  int _subtaskIndexById(List<QuestSubtask> subtasks, String subtaskId) {
    for (var index = 0; index < subtasks.length; index += 1) {
      if (subtasks[index].id == subtaskId) {
        return index;
      }
    }
    return -1;
  }

  int _sumSubtaskElapsedSeconds(List<QuestSubtask> subtasks) {
    var total = 0;
    for (final subtask in subtasks) {
      total += subtask.clampedElapsedSeconds;
    }
    return total;
  }

  int _clampElapsedSeconds(int elapsedSeconds, int durationSeconds) {
    if (elapsedSeconds < 0) {
      return 0;
    }
    if (durationSeconds > 0 && elapsedSeconds > durationSeconds) {
      return durationSeconds;
    }
    return elapsedSeconds;
  }

  int _nonNegativeElapsedSeconds(int elapsedSeconds) {
    if (elapsedSeconds < 0) {
      return 0;
    }
    return elapsedSeconds;
  }

  void _stopLocalTicker() {
    _localTicker?.cancel();
    _localTicker = null;
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  void _listenToBackgroundTimer() {
    _questTimerTickSubscription = _questTimerService.timerTicks.listen((tick) {
      if (!mounted || tick.questId != _quest.id) {
        return;
      }

      final nextElapsedSeconds = _nonNegativeElapsedSeconds(tick.elapsedSeconds);
      if (_localTicker != null && tick.isRunning) {
        return;
      }

      if (nextElapsedSeconds < _elapsedSeconds) {
        if (!tick.isRunning) {
          _stopLocalTicker();
        }
        setState(() {
          _running = tick.isRunning;
          _hasStarted = _elapsedSeconds > 0 || tick.isRunning;
        });
        return;
      }

      final elapsedDelta = nextElapsedSeconds - _elapsedSeconds;
      if (elapsedDelta > 0) {
        _advanceQuestProgress(
          elapsedDelta,
          running: tick.isRunning,
          hasStarted: tick.elapsedSeconds > 0 || tick.isRunning,
        );
      } else {
        if (!tick.isRunning) {
          _stopLocalTicker();
        }
        setState(() {
          _elapsedSeconds = nextElapsedSeconds;
          _quest = _quest.copyWith(elapsedSeconds: nextElapsedSeconds);
          _running = tick.isRunning;
          _hasStarted = tick.elapsedSeconds > 0 || tick.isRunning;
        });
      }

      if (tick.isRunning && _localTicker == null) {
        _startLocalTicker();
      }
    });

    unawaited(_syncBackgroundTimerState());
  }

  Future<void> _syncBackgroundTimerState() async {
    final snapshot = await _questTimerService.currentState();
    if (!mounted || snapshot == null || snapshot.questId != _quest.id) {
      return;
    }

    final shouldStartCountdown = snapshot.isRunning;

    final nextElapsedSeconds = _nonNegativeElapsedSeconds(snapshot.elapsedSeconds);
    if (nextElapsedSeconds < _elapsedSeconds) {
      if (!snapshot.isRunning) {
        _stopLocalTicker();
      }
      setState(() {
        _running = snapshot.isRunning;
        _hasStarted = _elapsedSeconds > 0 || snapshot.isRunning;
      });
      return;
    }

    final elapsedDelta = nextElapsedSeconds - _elapsedSeconds;
    if (elapsedDelta > 0) {
      _advanceQuestProgress(
        elapsedDelta,
        running: snapshot.isRunning,
        hasStarted: snapshot.elapsedSeconds > 0 || snapshot.isRunning,
      );
    } else {
      setState(() {
        _elapsedSeconds = nextElapsedSeconds;
        _quest = _quest.copyWith(elapsedSeconds: nextElapsedSeconds);
        _running = snapshot.isRunning;
        _hasStarted = snapshot.elapsedSeconds > 0 || snapshot.isRunning;
      });
    }

    if (shouldStartCountdown) {
      _startLocalTicker();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _countDownController.start();
      });
    }
  }
}

class _SubtaskAdvanceResult {
  const _SubtaskAdvanceResult({
    required this.subtasks,
    required this.activeSubtaskId,
    required this.appliedSeconds,
  });

  final List<QuestSubtask> subtasks;
  final String? activeSubtaskId;
  final int appliedSeconds;
}

class _TimerResetTarget {
  const _TimerResetTarget._(this.subtaskId);

  const _TimerResetTarget.all() : this._(null);

  const _TimerResetTarget.subtask(String subtaskId) : this._(subtaskId);

  final String? subtaskId;
}
