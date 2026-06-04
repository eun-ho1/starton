import 'package:flutter/material.dart';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart' as neu;
import 'package:start_on/models/app_local_data.dart';

enum AddQuestScreenResult { deleteQuest }

class AddQuestScreenAiSuggestionRequest {
  const AddQuestScreenAiSuggestionRequest(this.draft);

  final QuestItem draft;
}

class AddQuestScreen extends StatefulWidget {
  const AddQuestScreen({
    super.key,
    this.initialCategory,
    this.initialQuest,
    this.title = 'Create New Task',
    this.submitLabel = 'Create task',
    this.showDeleteAction = false,
    this.returnAiSuggestionRequest = false,
  });

  final String? initialCategory;
  final QuestItem? initialQuest;
  final String title;
  final String submitLabel;
  final bool showDeleteAction;
  final bool returnAiSuggestionRequest;

  @override
  State<AddQuestScreen> createState() => _AddQuestScreenState();
}

class _AddQuestScreenState extends State<AddQuestScreen> {
  static const List<String> _difficultyOptions = ['쉬움', '보통', '어려움'];
  static const List<String> _categoryOptions = [
    'home',
    'study',
    'work',
    'life',
  ];
  static const Color _dialogColor = Color(0xFFF1F2F6);
  static const Color _labelColor = Color(0xFF8A8E98);
  static const Color _titleColor = Color(0xFF111111);

  final TextEditingController _controller = TextEditingController();
  final TextEditingController _manualSubtasksController =
      TextEditingController();
  final FocusNode _titleFocusNode = FocusNode();
  final FocusNode _manualSubtasksFocusNode = FocusNode();

  String _difficulty = '보통';
  String _category = 'work';
  bool _usesManualSubtasks = false;
  String? _subtaskError;
  DateTime? _dueDate;

  @override
  void initState() {
    super.initState();
    final initialQuest = widget.initialQuest;
    if (initialQuest != null) {
      _controller.text = initialQuest.title;
      _difficulty = initialQuest.difficulty;
      _category = normalizeQuestCategory(initialQuest.category);
      _dueDate = normalizeQuestDueDate(initialQuest.dueDate);
      if (initialQuest.subtasks.isNotEmpty) {
        _usesManualSubtasks = true;
        _manualSubtasksController.text = _subtaskLinesFromQuest(initialQuest);
      }
      return;
    }

    _dueDate = _todayDueDate();

    final initialCategory = widget.initialCategory;
    if (initialCategory != null && questCategories.contains(initialCategory)) {
      _category = initialCategory;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _manualSubtasksController.dispose();
    _titleFocusNode.dispose();
    _manualSubtasksFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final canDeleteQuest = _canDeleteQuest;

    return Scaffold(
      backgroundColor: _dialogColor,
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(28, 24, 28, 40 + viewInsets.bottom),
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(
                          Icons.arrow_back_rounded,
                          color: Color(0xFF2C2F36),
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    const Spacer(),
                    if (canDeleteQuest)
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: IconButton(
                          key: const Key('add_quest.delete_button'),
                          tooltip: '퀘스트 삭제',
                          onPressed: _confirmDeleteQuest,
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 22,
                            color: Color(0xFFE55353),
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 18),
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: _AddQuestScreenState._titleColor,
                  ),
                ),
                const SizedBox(height: 14),
                const _DialogSectionLabel('Title'),
                const SizedBox(height: 8),
                FractionallySizedBox(
                  widthFactor: 0.86,
                  child: TextField(
                    controller: _controller,
                    focusNode: _titleFocusNode,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: _AddQuestScreenState._titleColor,
                    ),
                    decoration: InputDecoration(
                      hintText: '퀘스트 제목을 입력하세요',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFD),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFE2E7F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Color(0xFF6F63FF),
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const _DialogSectionLabel('Due Date'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: _pickDueDate,
                        behavior: HitTestBehavior.opaque,
                        child: _InsetFieldShell(
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _dueDate == null
                                      ? '마감일 없음'
                                      : formatQuestDueDate(_dueDate!),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: _dueDate == null
                                        ? const Color(0xFFB7BCC7)
                                        : _AddQuestScreenState._titleColor,
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Color(0xFF1F1F1F),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    GestureDetector(
                      onTap: _pickDueDate,
                      child: neu.Neumorphic(
                        style: const neu.NeumorphicStyle(
                          depth: 6,
                          intensity: 0.95,
                          surfaceIntensity: 0.24,
                          color: Color(0xFFDAD3FF),
                          shadowDarkColor: Color(0x26000000),
                          shadowLightColor: Color(0xFFFFFFFF),
                          boxShape: neu.NeumorphicBoxShape.circle(),
                        ),
                        padding: const EdgeInsets.all(14),
                        child: const Icon(
                          Icons.calendar_month_rounded,
                          size: 22,
                          color: Color(0xFF171717),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _NoDueDateButton(
                  selected: _dueDate == null,
                  onTap: _clearDueDate,
                ),
                const SizedBox(height: 14),
                const _DialogSectionLabel('Level'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (var i = 0; i < _difficultyOptions.length; i++) ...[
                      Expanded(
                        child: _LevelChip(
                          label: _difficultyOptions[i],
                          selected: _difficultyOptions[i] == _difficulty,
                          onTap: () => setState(
                            () => _difficulty = _difficultyOptions[i],
                          ),
                        ),
                      ),
                      if (i != _difficultyOptions.length - 1)
                        const SizedBox(width: 14),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                const _DialogSectionLabel('Category'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (var i = 0; i < _categoryOptions.length; i++) ...[
                      Expanded(
                        child: _CategoryChip(
                          label: questCategoryLabel(
                            _categoryOptions[i],
                          ).toUpperCase(),
                          selected: _categoryOptions[i] == _category,
                          style: _categoryChipStyleFor(_categoryOptions[i]),
                          onTap: () =>
                              setState(() => _category = _categoryOptions[i]),
                        ),
                      ),
                      if (i != _categoryOptions.length - 1)
                        const SizedBox(width: 10),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                const _DialogSectionLabel('Subtasks'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _SubtaskModeChip(
                        label: 'AI로 생성',
                        icon: Icons.auto_awesome_rounded,
                        selected: !_usesManualSubtasks,
                        onTap: () => setState(() {
                          _usesManualSubtasks = false;
                          _subtaskError = null;
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SubtaskModeChip(
                        label: '직접 입력',
                        icon: Icons.edit_note_rounded,
                        selected: _usesManualSubtasks,
                        onTap: () => setState(() {
                          _usesManualSubtasks = true;
                          _subtaskError = null;
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_usesManualSubtasks)
                  TextField(
                    controller: _manualSubtasksController,
                    focusNode: _manualSubtasksFocusNode,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    minLines: 5,
                    maxLines: 5,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: _AddQuestScreenState._titleColor,
                    ),
                    decoration: InputDecoration(
                      hintText: '자료 조사 / 10분\n핵심 정리 / 15분',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFD),
                      contentPadding: const EdgeInsets.all(16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFE2E7F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(
                          color: Color(0xFF6F63FF),
                          width: 1.4,
                        ),
                      ),
                    ),
                  )
                else
                  _AiSuggestionButton(onTap: _handleAiSuggestionTap),
                if (_subtaskError != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _subtaskError!,
                    style: const TextStyle(
                      color: Color(0xFFE55353),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 58,
                  child: GestureDetector(
                    onTap: _submit,
                    child: neu.Neumorphic(
                      style: neu.NeumorphicStyle(
                        depth: 6,
                        intensity: 0.95,
                        surfaceIntensity: 0.2,
                        color: const Color(0xFF6B9AF5),
                        shadowDarkColor: const Color(0x66000000),
                        shadowLightColor: Colors.white,
                        boxShape: neu.NeumorphicBoxShape.roundRect(
                          BorderRadius.circular(29),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          widget.submitLabel,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool get _canDeleteQuest =>
      widget.showDeleteAction && widget.initialQuest != null;

  Future<void> _confirmDeleteQuest() async {
    if (!_canDeleteQuest) {
      return;
    }

    FocusScope.of(context).unfocus();
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('퀘스트 삭제'),
          content: const Text('이 퀘스트를 삭제할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFE55353),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('삭제'),
            ),
          ],
        );
      },
    );

    if (!mounted || shouldDelete != true) {
      return;
    }

    Navigator.of(context).pop(AddQuestScreenResult.deleteQuest);
  }

  Future<void> _handleAiSuggestionTap() async {
    final selection = await _openAiPromptSelectionPage();
    if (!mounted || selection == null) {
      return;
    }

    final draft = _questFromInput();
    if (draft == null) {
      return;
    }
    final aiDraft = draft.copyWith(
      aiSubtaskPrompt: selection.promptInstruction,
    );

    if (!widget.returnAiSuggestionRequest) {
      Navigator.of(context).pop(aiDraft);
      return;
    }

    Navigator.of(context).pop(AddQuestScreenAiSuggestionRequest(aiDraft));
  }

  Future<_AiPromptSelection?> _openAiPromptSelectionPage() {
    return Navigator.of(context).push<_AiPromptSelection>(
      MaterialPageRoute<_AiPromptSelection>(
        builder: (_) => const _AiPromptSelectionPage(),
      ),
    );
  }

  void _submit() {
    final quest = _questFromInput();
    if (quest == null) {
      return;
    }

    Navigator.of(context).pop(quest);
  }

  QuestItem? _questFromInput() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      return null;
    }

    final initialQuest = widget.initialQuest;
    final exp = expForDifficulty(_difficulty);
    final subtasks = _usesManualSubtasks
        ? _parseManualSubtasks(initialQuest: initialQuest)
        : const <QuestSubtask>[];
    if (_usesManualSubtasks && subtasks.isEmpty) {
      setState(() => _subtaskError = 'subtask를 한 줄 이상 입력해 주세요.');
      return null;
    }
    final activeSubtaskId = _activeSubtaskIdFor(subtasks);

    return (initialQuest ??
            QuestItem(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              title: '',
              exp: exp,
              difficulty: _difficulty,
              category: _category,
              elapsedSeconds: 0,
              defaultDurationSeconds: defaultQuestDurationSecondsForDifficulty(
                _difficulty,
              ),
              dueDate: _dueDate,
            ))
        .copyWith(
          title: name,
          exp: exp,
          difficulty: _difficulty,
          category: _category,
          elapsedSeconds: initialQuest?.elapsedSeconds ?? 0,
          defaultDurationSeconds: defaultQuestDurationSecondsForDifficulty(
            _difficulty,
          ),
          dueDate: _dueDate,
          subtasks: subtasks,
          activeSubtaskId: activeSubtaskId,
          aiSubtaskPrompt: null,
        );
  }

  List<QuestSubtask> _parseManualSubtasks({QuestItem? initialQuest}) {
    final lines = _manualSubtasksController.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final baseId =
        initialQuest?.id ?? DateTime.now().microsecondsSinceEpoch.toString();

    return [
      for (var index = 0; index < lines.length; index += 1)
        _subtaskFromLine(
          lines[index],
          index: index,
          fallbackId: 'manual-subtask-$baseId-$index',
          previousSubtask:
              initialQuest == null || index >= initialQuest.subtasks.length
              ? null
              : initialQuest.subtasks[index],
        ),
    ];
  }

  QuestSubtask _subtaskFromLine(
    String line, {
    required int index,
    required String fallbackId,
    QuestSubtask? previousSubtask,
  }) {
    final parsed = _parseSubtaskLine(line);
    return QuestSubtask(
      id: previousSubtask?.id ?? fallbackId,
      title: parsed.title,
      orderIndex: index,
      estimatedMinutes: parsed.estimatedMinutes,
      status: previousSubtask?.status ?? 'todo',
      isNextAction: index == 0,
      energyRequired: previousSubtask?.energyRequired,
      completedAt: previousSubtask?.completedAt,
      elapsedSeconds: previousSubtask?.elapsedSeconds ?? 0,
    );
  }

  _ParsedSubtaskLine _parseSubtaskLine(String line) {
    var title = line;
    var estimatedMinutes = 10;
    final separatorIndex = line.lastIndexOf('/');

    if (separatorIndex >= 0) {
      title = line.substring(0, separatorIndex).trim();
      final rawMinutes = line.substring(separatorIndex + 1).trim();
      estimatedMinutes = _parseMinutes(rawMinutes) ?? estimatedMinutes;
    }

    final normalizedTitle = title.isEmpty ? line.trim() : title;
    return _ParsedSubtaskLine(
      title: normalizedTitle,
      estimatedMinutes: estimatedMinutes,
    );
  }

  int? _parseMinutes(String value) {
    final match = RegExp(r'(\d+)').firstMatch(value);
    if (match == null) {
      return null;
    }
    final minutes = int.tryParse(match.group(1)!);
    if (minutes == null || minutes <= 0) {
      return null;
    }
    return minutes;
  }

  String _subtaskLinesFromQuest(QuestItem quest) {
    return quest.subtasks
        .map((subtask) {
          final minutes = subtask.estimatedMinutes ?? 10;
          return '${subtask.title} / $minutes분';
        })
        .join('\n');
  }

  String? _activeSubtaskIdFor(List<QuestSubtask> subtasks) {
    for (final subtask in subtasks) {
      if (!subtask.isDone) {
        return subtask.id;
      }
    }
    if (subtasks.isEmpty) {
      return null;
    }
    return subtasks.first.id;
  }

  void _clearDueDate() {
    setState(() => _dueDate = null);
  }

  DateTime _todayDueDate() => normalizeQuestDueDate(DateTime.now())!;

  Future<void> _pickDueDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: '마감일 선택',
      cancelText: '취소',
      confirmText: '확인',
    );
    if (!mounted || picked == null) {
      return;
    }

    setState(() => _dueDate = normalizeQuestDueDate(picked));
  }
}

int expForDifficulty(String difficulty) {
  return switch (difficulty) {
    '쉬움' => 30,
    '보통' => 50,
    _ => 100,
  };
}

class _DialogSectionLabel extends StatelessWidget {
  const _DialogSectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: _AddQuestScreenState._labelColor,
      ),
    );
  }
}

class _InsetFieldShell extends StatelessWidget {
  const _InsetFieldShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 14);

    return neu.Neumorphic(
      style: neu.NeumorphicStyle(
        depth: -4,
        intensity: 0.8,
        surfaceIntensity: 0.12,
        color: _AddQuestScreenState._dialogColor,
        shadowDarkColor: Color(0x18000000),
        shadowLightColor: Color(0xFFFFFFFF),
        boxShape: neu.NeumorphicBoxShape.roundRect(
          BorderRadius.all(Radius.circular(16)),
        ),
      ),
      padding: padding,
      child: SizedBox(height: 48 - padding.vertical, child: child),
    );
  }
}

class _NoDueDateButton extends StatelessWidget {
  const _NoDueDateButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const Key('add_quest.no_due_date_button'),
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: neu.Neumorphic(
          style: neu.NeumorphicStyle(
            depth: selected ? -3.5 : 5,
            intensity: selected ? 0.8 : 0.95,
            surfaceIntensity: selected ? 0.12 : 0.2,
            color: selected
                ? const Color(0xFFE7E3FF)
                : _AddQuestScreenState._dialogColor,
            shadowDarkColor: selected
                ? const Color(0x18000000)
                : const Color(0x33000000),
            shadowLightColor: Colors.white,
            boxShape: neu.NeumorphicBoxShape.roundRect(
              BorderRadius.circular(14),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.event_busy_rounded,
                size: 18,
                color: selected
                    ? const Color(0xFF6F63FF)
                    : const Color(0xFF5F6673),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  '마감일 없음',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF252B3A)
                        : const Color(0xFF5F6673),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtaskModeChip extends StatelessWidget {
  const _SubtaskModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: neu.Neumorphic(
          style: neu.NeumorphicStyle(
            depth: selected ? -3.5 : 5,
            intensity: selected ? 0.8 : 0.95,
            surfaceIntensity: selected ? 0.12 : 0.2,
            color: _AddQuestScreenState._dialogColor,
            shadowDarkColor: selected
                ? const Color(0x18000000)
                : const Color(0x33000000),
            shadowLightColor: Colors.white,
            boxShape: neu.NeumorphicBoxShape.roundRect(
              BorderRadius.circular(14),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 18,
                color: selected
                    ? const Color(0xFF6F63FF)
                    : const Color(0xFF5F6673),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected
                        ? const Color(0xFF252B3A)
                        : const Color(0xFF5F6673),
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const _aiPromptOptions = [
  _AiPromptOption(
    id: 'small_steps',
    title: '작게 쪼개기',
    description: '퀘스트를 바로 실행 가능한 작은 단계로 나눠요.',
    instruction: '퀘스트를 바로 실행 가능한 작은 단계 중심으로 쪼갭니다.',
    icon: Icons.account_tree_rounded,
  ),
  _AiPromptOption(
    id: 'focus_routine',
    title: '집중 루틴',
    description: '시간 배분과 순서를 정리한 집중형 플랜을 만들어요.',
    instruction: '집중 흐름에 맞춰 순서와 시간 배분을 함께 정리합니다.',
    icon: Icons.timer_outlined,
  ),
  _AiPromptOption(
    id: 'quick_action',
    title: '빠른 실행',
    description: '핵심 작업만 추려 짧고 단순한 제안을 만들어요.',
    instruction: '핵심 작업만 남겨 짧고 단순한 실행 단계로 제안합니다.',
    icon: Icons.flash_on_rounded,
  ),
];

const _timeAllocationOptions = [
  _TimeAllocationOption(
    id: 'equal',
    title: '시간배분 모두 똑같이',
    description: '모든 subtask에 비슷한 시간을 배정해요.',
    instruction: '모든 subtask에 시간을 균등하게 배분합니다.',
    bars: [30, 30, 30],
  ),
  _TimeAllocationOption(
    id: 'middle_peak',
    title: '가운데에 시간이 가장 길게',
    description: '시작과 끝은 짧게, 핵심 구간에 시간을 더 써요.',
    instruction: '시작과 마무리는 짧게 잡고 가운데 핵심 subtask에 가장 긴 시간을 배분합니다.',
    bars: [18, 40, 18],
  ),
  _TimeAllocationOption(
    id: 'progressive',
    title: '점점 시간을 많이 쓰기',
    description: '뒤로 갈수록 더 긴 시간이 필요하게 배정해요.',
    instruction: '초반 subtask는 짧게 시작하고 뒤로 갈수록 더 긴 시간을 배분합니다.',
    bars: [16, 28, 42],
  ),
];

class _AiPromptSelection {
  const _AiPromptSelection({
    required this.promptOption,
    required this.timeAllocation,
  });

  final _AiPromptOption promptOption;
  final _TimeAllocationOption timeAllocation;

  String get promptInstruction {
    return [
      'subtask_prompt_mode=${promptOption.id}',
      promptOption.instruction,
      'time_allocation=${timeAllocation.id}',
      timeAllocation.instruction,
    ].join('\n');
  }
}

class _AiPromptSelectionPage extends StatefulWidget {
  const _AiPromptSelectionPage();

  @override
  State<_AiPromptSelectionPage> createState() => _AiPromptSelectionPageState();
}

class _AiPromptSelectionPageState extends State<_AiPromptSelectionPage> {
  int _selectedPromptIndex = 0;
  int _selectedTimeIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AddQuestScreenState._dialogColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 32),
          children: [
            Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.arrow_back_rounded,
                      color: Color(0xFF2C2F36),
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const Expanded(
                  child: Center(
                    child: Text(
                      'AI 프롬프트 선택',
                      style: TextStyle(
                        color: _AddQuestScreenState._titleColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 40, height: 40),
              ],
            ),
            const SizedBox(height: 22),
            const _DialogSectionLabel('쪼개기 선택'),
            const SizedBox(height: 10),
            for (
              var index = 0;
              index < _aiPromptOptions.length;
              index += 1
            ) ...[
              _AiPromptOptionTile(
                option: _aiPromptOptions[index],
                selected: _selectedPromptIndex == index,
                onTap: () => setState(() => _selectedPromptIndex = index),
              ),
              if (index != _aiPromptOptions.length - 1)
                const SizedBox(height: 10),
            ],
            const SizedBox(height: 24),
            const _DialogSectionLabel('Subtask 시간분배'),
            const SizedBox(height: 10),
            for (
              var index = 0;
              index < _timeAllocationOptions.length;
              index += 1
            ) ...[
              _TimeAllocationOptionTile(
                option: _timeAllocationOptions[index],
                selected: _selectedTimeIndex == index,
                onTap: () => setState(() => _selectedTimeIndex = index),
              ),
              if (index != _timeAllocationOptions.length - 1)
                const SizedBox(height: 10),
            ],
            const SizedBox(height: 28),
            GestureDetector(
              onTap: () => Navigator.of(context).pop(
                _AiPromptSelection(
                  promptOption: _aiPromptOptions[_selectedPromptIndex],
                  timeAllocation: _timeAllocationOptions[_selectedTimeIndex],
                ),
              ),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: neu.Neumorphic(
                  style: neu.NeumorphicStyle(
                    depth: 6,
                    intensity: 0.95,
                    surfaceIntensity: 0.2,
                    color: const Color(0xFF6B9AF5),
                    shadowDarkColor: const Color(0x66000000),
                    shadowLightColor: Colors.white,
                    boxShape: neu.NeumorphicBoxShape.roundRect(
                      BorderRadius.circular(28),
                    ),
                  ),
                  child: const Center(
                    child: Text(
                      '다음',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AiPromptOption {
  const _AiPromptOption({
    required this.id,
    required this.title,
    required this.description,
    required this.instruction,
    required this.icon,
  });

  final String id;
  final String title;
  final String description;
  final String instruction;
  final IconData icon;
}

class _TimeAllocationOption {
  const _TimeAllocationOption({
    required this.id,
    required this.title,
    required this.description,
    required this.instruction,
    required this.bars,
  });

  final String id;
  final String title;
  final String description;
  final String instruction;
  final List<int> bars;
}

class _AiPromptOptionTile extends StatelessWidget {
  const _AiPromptOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _AiPromptOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE7E3FF) : const Color(0xFFF8FAFD),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFF6F63FF) : const Color(0xFFE2E7F0),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              option.icon,
              size: 22,
              color: selected
                  ? const Color(0xFF6358FF)
                  : _AddQuestScreenState._labelColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                      color: _AddQuestScreenState._titleColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    option.description,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _AddQuestScreenState._labelColor,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 19,
              color: selected
                  ? const Color(0xFF6358FF)
                  : _AddQuestScreenState._labelColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeAllocationOptionTile extends StatelessWidget {
  const _TimeAllocationOptionTile({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final _TimeAllocationOption option;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE7E3FF) : const Color(0xFFF8FAFD),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFF6F63FF) : const Color(0xFFE2E7F0),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            _MiniTimeAllocationGraph(bars: option.bars, selected: selected),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _AddQuestScreenState._titleColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    option.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _AddQuestScreenState._labelColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              size: 19,
              color: selected
                  ? const Color(0xFF6358FF)
                  : _AddQuestScreenState._labelColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniTimeAllocationGraph extends StatelessWidget {
  const _MiniTimeAllocationGraph({required this.bars, required this.selected});

  final List<int> bars;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final barColor = selected
        ? const Color(0xFF6358FF)
        : const Color(0xFF9AA2B1);

    return SizedBox(
      width: 52,
      height: 46,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var index = 0; index < bars.length; index += 1) ...[
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: bars[index].toDouble(),
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
            ),
            if (index != bars.length - 1) const SizedBox(width: 5),
          ],
        ],
      ),
    );
  }
}

class _AiSuggestionButton extends StatelessWidget {
  const _AiSuggestionButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: double.infinity,
        height: 58,
        child: neu.Neumorphic(
          style: neu.NeumorphicStyle(
            depth: 6,
            intensity: 0.95,
            surfaceIntensity: 0.2,
            color: const Color(0xFFDAD3FF),
            shadowDarkColor: const Color(0x26000000),
            shadowLightColor: Colors.white,
            boxShape: neu.NeumorphicBoxShape.roundRect(
              BorderRadius.circular(18),
            ),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 20,
                color: Color(0xFF6358FF),
              ),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'AI 제안 페이지로 이동',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Color(0xFF252B3A),
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  const _LevelChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: neu.Neumorphic(
          style: neu.NeumorphicStyle(
            depth: selected ? -4 : 6,
            intensity: selected ? 0.8 : 0.95,
            surfaceIntensity: selected ? 0.12 : 0.2,
            color: selected
                ? const Color(0xFFDAD3FF)
                : _AddQuestScreenState._dialogColor,
            shadowDarkColor: selected
                ? const Color(0x18000000)
                : const Color(0x33000000),
            shadowLightColor: Colors.white,
            boxShape: neu.NeumorphicBoxShape.roundRect(
              BorderRadius.circular(14),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1B1B1B),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.style,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final _CategoryChipStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = selected ? style.selectedTextColor : style.textColor;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        height: 42,
        child: neu.Neumorphic(
          style: neu.NeumorphicStyle(
            depth: selected ? -3.5 : 5,
            intensity: selected ? 0.8 : 0.95,
            surfaceIntensity: selected ? 0.12 : 0.2,
            color: selected
                ? const Color(0xFFDAD3FF)
                : _AddQuestScreenState._dialogColor,
            shadowDarkColor: selected
                ? const Color(0x18000000)
                : const Color(0x33000000),
            shadowLightColor: Colors.white,
            boxShape: neu.NeumorphicBoxShape.roundRect(
              BorderRadius.circular(12),
            ),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ParsedSubtaskLine {
  const _ParsedSubtaskLine({
    required this.title,
    required this.estimatedMinutes,
  });

  final String title;
  final int estimatedMinutes;
}

class _CategoryChipStyle {
  const _CategoryChipStyle({
    required this.selectedTextColor,
    required this.textColor,
  });

  final Color selectedTextColor;
  final Color textColor;
}

_CategoryChipStyle _categoryChipStyleFor(String category) {
  return switch (category) {
    'home' => const _CategoryChipStyle(
      selectedTextColor: Color(0xFFF79685),
      textColor: Color(0xFFF39482),
    ),
    'study' => const _CategoryChipStyle(
      selectedTextColor: Color(0xFFFFD954),
      textColor: Color(0xFFF4CE46),
    ),
    'work' => const _CategoryChipStyle(
      selectedTextColor: Color(0xFF68B3AD),
      textColor: Color(0xFF63ADA8),
    ),
    'life' => const _CategoryChipStyle(
      selectedTextColor: Color(0xFFA8BFAA),
      textColor: Color(0xFFA7BFA8),
    ),
    _ => const _CategoryChipStyle(
      selectedTextColor: Color(0xFF111111),
      textColor: Color(0xFF6C7480),
    ),
  };
}
