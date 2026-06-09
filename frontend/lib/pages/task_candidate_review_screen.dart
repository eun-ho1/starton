import 'package:flutter/material.dart';
import 'package:start_on/models/task_intake_api_models.dart';
import 'package:start_on/widgets/common.dart';

enum TaskCandidateReviewAction {
  saveAsIs,
  saveTodayOnly,
  makeSmaller,
  reduceReminders,
  cancel,
}

class TaskCandidateReviewResult {
  const TaskCandidateReviewResult({
    required this.action,
    required this.candidateId,
    this.selectedSubtaskIds = const <String>[],
    this.selectedReminderIds = const <String>[],
    this.editedFields = const <String, dynamic>{},
  });

  final TaskCandidateReviewAction action;
  final String candidateId;
  final List<String> selectedSubtaskIds;
  final List<String> selectedReminderIds;
  final Map<String, dynamic> editedFields;
}

class TaskCandidateReviewScreen extends StatefulWidget {
  const TaskCandidateReviewScreen({required this.candidate, super.key});

  final TaskCandidateResponse candidate;

  @override
  State<TaskCandidateReviewScreen> createState() =>
      _TaskCandidateReviewScreenState();
}

class _TaskCandidateReviewScreenState extends State<TaskCandidateReviewScreen> {
  static const Color _backgroundColor = Color(0xFFF1F3F8);
  static const Color _titleColor = Color(0xFF172033);
  static const Color _bodyColor = Color(0xFF4F5B70);
  static const Color _primaryColor = Color(0xFF6F63FF);
  static const Color _secondaryColor = Color(0xFF6B9AF5);

  late Set<String> _selectedSubtaskIds;
  late Set<String> _selectedReminderIds;

  @override
  void initState() {
    super.initState();
    _selectedSubtaskIds = widget.candidate.subtasks
        .map((subtask) => subtask.id)
        .toSet();
    _selectedReminderIds = widget.candidate.reminders
        .where((reminder) => reminder.remindAt != null)
        .map((reminder) => reminder.id)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    final candidate = widget.candidate;

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  _Header(onCancel: _cancel),
                  const SizedBox(height: 20),
                  _SummaryCard(candidate: candidate),
                  const SizedBox(height: 14),
                  _TodayRecommendationCard(candidate: candidate),
                  if (candidate.overloadWarning != null) ...[
                    const SizedBox(height: 14),
                    _WarningBand(message: candidate.overloadWarning!),
                  ],
                  const SizedBox(height: 20),
                  _ReviewSection(
                    icon: Icons.checklist_rounded,
                    title: '세부 단계',
                    child: _SubtaskList(
                      subtasks: candidate.subtasks,
                      selectedIds: _selectedSubtaskIds,
                      onToggle: _toggleSubtask,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _ReviewSection(
                    icon: Icons.notifications_active_outlined,
                    title: '리마인더',
                    child: _ReminderList(
                      reminders: candidate.reminders,
                      selectedIds: _selectedReminderIds,
                      onToggle: _toggleReminder,
                    ),
                  ),
                ],
              ),
            ),
            _ActionPanel(
              onSaveAsIs: () => _popWith(TaskCandidateReviewAction.saveAsIs),
              onSaveTodayOnly: () =>
                  _popWith(TaskCandidateReviewAction.saveTodayOnly),
              onMakeSmaller: () =>
                  _popWith(TaskCandidateReviewAction.makeSmaller),
              onReduceReminders: () =>
                  _popWith(TaskCandidateReviewAction.reduceReminders),
              onCancel: _cancel,
            ),
          ],
        ),
      ),
    );
  }

  void _toggleSubtask(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedSubtaskIds.add(id);
      } else {
        _selectedSubtaskIds.remove(id);
      }
    });
  }

  void _toggleReminder(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedReminderIds.add(id);
      } else {
        _selectedReminderIds.remove(id);
      }
    });
  }

  void _cancel() {
    _popWith(TaskCandidateReviewAction.cancel);
  }

  void _popWith(TaskCandidateReviewAction action) {
    final selectedReminderIds = widget.candidate.reminders
        .where(
          (reminder) =>
              reminder.remindAt != null &&
              _selectedReminderIds.contains(reminder.id),
        )
        .map((reminder) => reminder.id)
        .toList(growable: false);
    Navigator.of(context).pop(
      TaskCandidateReviewResult(
        action: action,
        candidateId: widget.candidate.id,
        selectedSubtaskIds: _selectedSubtaskIds.toList(growable: false),
        selectedReminderIds: selectedReminderIds,
        editedFields: const <String, dynamic>{},
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: '뒤로가기',
          onPressed: onCancel,
          icon: const Icon(Icons.arrow_back_rounded),
          color: const Color(0xFF2C2F36),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          visualDensity: VisualDensity.compact,
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'AI 제안 확인',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: _TaskCandidateReviewScreenState._titleColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.candidate});

  final TaskCandidateResponse candidate;

  @override
  Widget build(BuildContext context) {
    final nextAction = candidate.nextAction;
    final chips = <Widget>[
      if (candidate.estimatedMinutes != null)
        _MetaChip(
          icon: Icons.schedule_rounded,
          label: '${candidate.estimatedMinutes}분',
        ),
      if (candidate.priority != null)
        _MetaChip(
          icon: Icons.flag_outlined,
          label: _priorityLabel(candidate.priority!),
        ),
      if (candidate.difficulty != null)
        _MetaChip(
          icon: Icons.terrain_outlined,
          label: _difficultyLabel(candidate.difficulty!),
        ),
      if (candidate.energyRequired != null)
        _MetaChip(
          icon: Icons.battery_charging_full_rounded,
          label: _energyLabel(candidate.energyRequired!),
        ),
    ];

    return NeumorphicRoundedCard(
      color: _TaskCandidateReviewScreenState._backgroundColor,
      padding: const EdgeInsets.all(20),
      borderRadius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '제안된 작업',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: Color(0xFF7B8496),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            candidate.title,
            style: const TextStyle(
              fontSize: 22,
              height: 1.2,
              fontWeight: FontWeight.w900,
              color: _TaskCandidateReviewScreenState._titleColor,
            ),
          ),
          if (nextAction != null) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: NeumorphicRoundedCard(
                padding: const EdgeInsets.all(16),
                color: _TaskCandidateReviewScreenState._backgroundColor,
                depth: -4,
                intensity: 0.82,
                surfaceIntensity: 0.12,
                borderRadius: 18,
                child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.play_arrow_rounded,
                    color: _TaskCandidateReviewScreenState._secondaryColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '다음 행동',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF6B7690),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          nextAction,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.35,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF243248),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                ),
              ),
            ),
          ],
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: chips),
          ],
        ],
      ),
    );
  }
}

class _TodayRecommendationCard extends StatelessWidget {
  const _TodayRecommendationCard({required this.candidate});

  final TaskCandidateResponse candidate;

  @override
  Widget build(BuildContext context) {
    final recommended = candidate.recommendedToday;
    final reason = candidate.todayReason;

    return SizedBox(
      width: double.infinity,
      child: NeumorphicRoundedCard(
        padding: const EdgeInsets.all(16),
        color: _TaskCandidateReviewScreenState._backgroundColor,
        depth: recommended ? 5 : -3,
        intensity: 0.86,
        surfaceIntensity: 0.16,
        borderRadius: 18,
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            recommended ? Icons.today_rounded : Icons.inbox_outlined,
            color: recommended
                ? const Color(0xFF2C9B62)
                : const Color(0xFF7B8496),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recommended ? '오늘 시작 추천' : '오늘은 보류 추천',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: _TaskCandidateReviewScreenState._titleColor,
                  ),
                ),
                if (reason != null) ...[
                  const SizedBox(height: 5),
                  Text(
                    reason,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: _TaskCandidateReviewScreenState._bodyColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _WarningBand extends StatelessWidget {
  const _WarningBand({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: NeumorphicRoundedCard(
        padding: const EdgeInsets.all(15),
        color: _TaskCandidateReviewScreenState._backgroundColor,
        depth: -3,
        intensity: 0.82,
        surfaceIntensity: 0.12,
        borderRadius: 16,
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFB26900)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: Color(0xFF5E3A00),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeading(icon: icon, title: title),
        const SizedBox(height: 10),
        child,
      ],
    );
  }
}

class _SubtaskList extends StatelessWidget {
  const _SubtaskList({
    required this.subtasks,
    required this.selectedIds,
    required this.onToggle,
  });

  final List<CandidateSubtaskResponse> subtasks;
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    if (subtasks.isEmpty) {
      return const _EmptyState(text: '제안된 세부 단계가 없어요.');
    }

    return Column(
      children: [
        for (final subtask in subtasks) ...[
          _SelectableTile(
            key: ValueKey('subtask-${subtask.id}'),
            selected: selectedIds.contains(subtask.id),
            onChanged: (selected) => onToggle(subtask.id, selected),
            title: subtask.title,
            subtitle: _subtaskSubtitle(subtask),
            trailing: subtask.isNextAction
                ? const _SmallBadge(label: '다음 행동')
                : null,
          ),
          if (subtask != subtasks.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ReminderList extends StatelessWidget {
  const _ReminderList({
    required this.reminders,
    required this.selectedIds,
    required this.onToggle,
  });

  final List<CandidateReminderResponse> reminders;
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    if (reminders.isEmpty) {
      return const _EmptyState(text: '제안된 리마인더가 없어요.');
    }

    return Column(
      children: [
        for (final reminder in reminders) ...[
          _SelectableTile(
            key: ValueKey('reminder-${reminder.id}'),
            enabled: reminder.remindAt != null,
            selected:
                reminder.remindAt != null && selectedIds.contains(reminder.id),
            onChanged: (selected) => onToggle(reminder.id, selected),
            title: reminder.message,
            subtitle: _reminderSubtitle(reminder),
            trailing: _SmallBadge(
              label: reminder.remindAt == null
                  ? '시간 없음'
                  : _reminderTypeLabel(reminder.type),
            ),
          ),
          if (reminder != reminders.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _SelectableTile extends StatelessWidget {
  const _SelectableTile({
    required this.selected,
    required this.onChanged,
    required this.title,
    required this.subtitle,
    this.enabled = true,
    this.trailing,
    super.key,
  });

  final bool selected;
  final ValueChanged<bool> onChanged;
  final String title;
  final String subtitle;
  final bool enabled;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = _TaskCandidateReviewScreenState._backgroundColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: enabled ? () => onChanged(!selected) : null,
        child: NeumorphicRoundedCard(
          padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
          color: color,
          depth: selected ? -4 : 5,
          intensity: 0.86,
          surfaceIntensity: selected ? 0.1 : 0.16,
          borderRadius: 18,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selected,
                activeColor: _TaskCandidateReviewScreenState._primaryColor,
                checkColor: color,
                onChanged: enabled
                    ? (value) => onChanged(value ?? false)
                    : null,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.3,
                          fontWeight: FontWeight.w800,
                          color: enabled
                              ? _TaskCandidateReviewScreenState._titleColor
                              : const Color(0xFF7B8496),
                        ),
                      ),
                      if (subtitle.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF768095),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: trailing,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.onSaveAsIs,
    required this.onSaveTodayOnly,
    required this.onMakeSmaller,
    required this.onReduceReminders,
    required this.onCancel,
  });

  final VoidCallback onSaveAsIs;
  final VoidCallback onSaveTodayOnly;
  final VoidCallback onMakeSmaller;
  final VoidCallback onReduceReminders;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        color: _TaskCandidateReviewScreenState._backgroundColor,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
        child: NeumorphicRoundedCard(
          color: _TaskCandidateReviewScreenState._backgroundColor,
          padding: const EdgeInsets.all(14),
          borderRadius: 22,
          depth: 6,
          intensity: 0.86,
          surfaceIntensity: 0.14,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onSaveAsIs,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('이대로 저장'),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        _TaskCandidateReviewScreenState._primaryColor,
                    foregroundColor:
                        _TaskCandidateReviewScreenState._backgroundColor,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 9),
              Row(
                children: [
                  Expanded(
                    child: _NeumorphicActionButton(
                      onPressed: onSaveTodayOnly,
                      icon: Icons.today_outlined,
                      label: '오늘 할 만큼만',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NeumorphicActionButton(
                      onPressed: onMakeSmaller,
                      icon: Icons.call_split_rounded,
                      label: '더 작게',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _NeumorphicActionButton(
                      onPressed: onReduceReminders,
                      icon: Icons.notifications_paused_outlined,
                      label: '리마인더 줄이기',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NeumorphicActionButton(
                      onPressed: onCancel,
                      icon: Icons.close_rounded,
                      label: '취소',
                      muted: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NeumorphicActionButton extends StatelessWidget {
  const _NeumorphicActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.muted = false,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final foreground = muted
        ? const Color(0xFF6C7480)
        : _TaskCandidateReviewScreenState._titleColor;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onPressed,
        child: NeumorphicRoundedCard(
          color: _TaskCandidateReviewScreenState._backgroundColor,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          borderRadius: 16,
          depth: 3.5,
          intensity: 0.82,
          surfaceIntensity: 0.12,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: foreground),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: foreground,
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

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return NeumorphicRoundedCard(
      color: _TaskCandidateReviewScreenState._backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      borderRadius: 999,
      depth: -2.5,
      intensity: 0.8,
      surfaceIntensity: 0.1,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 15,
            color: _TaskCandidateReviewScreenState._primaryColor,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF3A4660),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return NeumorphicRoundedCard(
      color: _TaskCandidateReviewScreenState._backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      borderRadius: 999,
      depth: -2,
      intensity: 0.78,
      surfaceIntensity: 0.1,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: _TaskCandidateReviewScreenState._secondaryColor,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: NeumorphicRoundedCard(
        color: _TaskCandidateReviewScreenState._backgroundColor,
        padding: const EdgeInsets.all(18),
        borderRadius: 18,
        depth: -3,
        intensity: 0.82,
        surfaceIntensity: 0.1,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF7B8496),
          ),
        ),
      ),
    );
  }
}

String _subtaskSubtitle(CandidateSubtaskResponse subtask) {
  final parts = <String>[
    if (subtask.estimatedMinutes != null) '${subtask.estimatedMinutes}분',
    if (subtask.energyRequired != null) _energyLabel(subtask.energyRequired!),
  ];
  return parts.join(' · ');
}

String _reminderSubtitle(CandidateReminderResponse reminder) {
  final parts = <String>[
    if (reminder.remindAt != null) _formatDateTime(reminder.remindAt!),
    _reminderTypeLabel(reminder.type),
    if (reminder.escalationLevel > 0) '${reminder.escalationLevel}단계',
  ];
  return parts.join(' · ');
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$month.$day $hour:$minute';
}

String _priorityLabel(String value) {
  return switch (value) {
    'low' => '낮음',
    'medium' => '보통',
    'high' => '높음',
    _ => value,
  };
}

String _difficultyLabel(String value) {
  return switch (value) {
    'low' => '쉬움',
    'medium' => '보통',
    'high' => '어려움',
    _ => value,
  };
}

String _energyLabel(String value) {
  return switch (value) {
    'low' => '낮은 에너지',
    'medium' => '중간 에너지',
    'high' => '높은 에너지',
    _ => value,
  };
}

String _reminderTypeLabel(String value) {
  return switch (value) {
    'start' => '시작',
    'deadline' => '마감',
    'nudge' => '넛지',
    'replan' => '재계획',
    _ => value,
  };
}
