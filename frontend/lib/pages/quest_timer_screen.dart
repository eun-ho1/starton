import 'dart:async';

import 'package:circular_countdown_timer/circular_countdown_timer.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:start_on/pages/add_quest_screen.dart';
import 'package:start_on/models/app_local_data.dart';
import 'package:start_on/pages/quest_timer/quest_timer_sections.dart';
import 'package:start_on/services/quest_timer_background_service.dart';
import 'package:start_on/storage/quest_image_store.dart';

typedef QuestAiSuggestionRequestHandler =
    Future<QuestItem?> Function({
      required QuestItem originalQuest,
      required QuestItem draft,
    });

class QuestTimerScreen extends StatefulWidget {
  const QuestTimerScreen({
    super.key,
    required this.quest,
    required this.userLevel,
    required this.notificationsEnabled,
    this.onQuestChanged,
    this.onAiSuggestionRequested,
  });

  final QuestItem quest;
  final int userLevel;
  final bool notificationsEnabled;
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
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final useLandscapeLayout =
                  constraints.maxWidth > constraints.maxHeight &&
                  constraints.maxWidth >= 640;

              return ListView(
                padding: EdgeInsets.fromLTRB(
                  useLandscapeLayout ? 30 : 22,
                  useLandscapeLayout ? 20 : 16,
                  useLandscapeLayout ? 30 : 22,
                  32,
                ),
                children: [
                  if (!useLandscapeLayout) ...[
                    QuestTimerHeader(
                      onBack: _popWithProgress,
                      onEdit: _editQuest,
                    ),
                    const SizedBox(height: 18),
                  ],
                  // 세로 화면은 기존 흐름을 유지하고, 가로 화면에서만 타이머를 오른쪽에 배치한다.
                  QuestTimerContentCard(
                    useLandscapeLayout: useLandscapeLayout,
                    questSummary: QuestTimerSummary(
                      quest: _quest,
                      userLevel: widget.userLevel,
                      earnedExp: _calculateEarnedExp(),
                      maxDurationSeconds: maxDurationSeconds,
                      onSubtaskSelect: _selectSubtask,
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
                      // 임시수정: 테스트 중에는 1분 제한 없이 바로 완료 가능하게 둔다.
                      canComplete: _elapsedSeconds >= 0,
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
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _handleTimerComplete() {
    if (!mounted || _isCompleting) {
      return;
    }
    unawaited(_completeQuest());
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

    if (_elapsedSeconds >= _durationSeconds) {
      final resetSubtasks = _resetSubtasks(_quest.subtasks);
      setState(() {
        _elapsedSeconds = 0;
        _quest = _quest.copyWith(
          elapsedSeconds: 0,
          subtasks: resetSubtasks,
          activeSubtaskId: _firstIncompleteSubtaskId(resetSubtasks),
        );
        _hasStarted = false;
        _timerViewRevision += 1;
      });
      widget.onQuestChanged?.call(_quest);
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
    if (_running && _elapsedSeconds < _durationSeconds) {
      _countDownController.pause();
    }

    _stopLocalTicker();

    if (widget.notificationsEnabled) {
      await _questTimerService.stopTimer();
    }

    if (!mounted) {
      return;
    }

    final resetSubtasks = _resetSubtasks(_quest.subtasks);
    setState(() {
      _elapsedSeconds = 0;
      _quest = _quest.copyWith(
        elapsedSeconds: 0,
        subtasks: resetSubtasks,
        activeSubtaskId: _firstIncompleteSubtaskId(resetSubtasks),
      );
      _hasStarted = false;
      _running = false;
      _timerViewRevision += 1;
    });
    widget.onQuestChanged?.call(_quest);
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

      final suggestedQuest = await suggestionHandler(
        originalQuest: _quest.copyWith(elapsedSeconds: _elapsedSeconds),
        draft: request.draft.copyWith(elapsedSeconds: _elapsedSeconds),
      );
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

      final shouldComplete = _advanceQuestProgress(1);
      if (shouldComplete) {
        unawaited(_completeQuest());
      }
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

    final durationSeconds = _durationSeconds;
    if (_quest.subtasks.isEmpty) {
      final nextElapsedSeconds = _clampElapsedSeconds(
        _elapsedSeconds + elapsedDeltaSeconds,
        durationSeconds,
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
      return nextElapsedSeconds >= durationSeconds;
    }

    final result = _advanceSubtasks(
      _quest.subtasks,
      activeSubtaskId: _quest.effectiveActiveSubtaskId,
      elapsedDeltaSeconds: elapsedDeltaSeconds,
      completedAt: DateTime.now(),
    );
    final nextElapsedSeconds = _clampElapsedSeconds(
      _elapsedSeconds + result.appliedSeconds,
      durationSeconds,
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

    return result.subtasks.isNotEmpty && result.activeSubtaskId == null;
  }

  QuestItem _normalizeQuestProgress(QuestItem quest) {
    if (quest.subtasks.isEmpty) {
      return quest.copyWith(
        elapsedSeconds: _clampElapsedSeconds(
          quest.elapsedSeconds,
          quest.effectiveDurationSeconds,
        ),
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
        elapsedSeconds: _clampElapsedSeconds(
          quest.elapsedSeconds,
          quest.effectiveDurationSeconds,
        ),
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
      elapsedSeconds: _clampElapsedSeconds(
        quest.elapsedSeconds,
        quest.effectiveDurationSeconds,
      ),
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

      final nextElapsedSeconds = _clampElapsedSeconds(
        tick.elapsedSeconds,
        _durationSeconds,
      );
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
      var shouldComplete = false;
      if (elapsedDelta > 0) {
        shouldComplete = _advanceQuestProgress(
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

      if (shouldComplete) {
        unawaited(_completeQuest());
      }
    });

    unawaited(_syncBackgroundTimerState());
  }

  Future<void> _syncBackgroundTimerState() async {
    final snapshot = await _questTimerService.currentState();
    if (!mounted || snapshot == null || snapshot.questId != _quest.id) {
      return;
    }

    final shouldStartCountdown =
        snapshot.isRunning && snapshot.elapsedSeconds < _durationSeconds;

    final nextElapsedSeconds = _clampElapsedSeconds(
      snapshot.elapsedSeconds,
      _durationSeconds,
    );
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
      final shouldComplete = _advanceQuestProgress(
        elapsedDelta,
        running: snapshot.isRunning,
        hasStarted: snapshot.elapsedSeconds > 0 || snapshot.isRunning,
      );
      if (shouldComplete) {
        unawaited(_completeQuest());
        return;
      }
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
