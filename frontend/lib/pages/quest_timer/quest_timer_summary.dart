import 'package:flutter/material.dart';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart' as neu;
import 'package:start_on/models/app_local_data.dart';

class QuestTimerSummary extends StatelessWidget {
  const QuestTimerSummary({
    super.key,
    required this.quest,
    required this.earnedExp,
    required this.maxDurationSeconds,
    this.onSubtaskSelect,
  });

  final QuestItem quest;
  final int earnedExp;
  final int maxDurationSeconds;
  final ValueChanged<String>? onSubtaskSelect;

  @override
  Widget build(BuildContext context) {
    final categoryStyle = questCategoryStyleFor(quest.category);
    final dueDate = quest.dueDate;
    final questLevel = _questDifficultyLevel(quest.difficulty);

    return SizedBox(
      key: const Key('quest_timer.title_box'),
      width: double.infinity,
      child: neu.Neumorphic(
        style: neu.NeumorphicStyle(
          depth: 7,
          intensity: 0.9,
          surfaceIntensity: 0.24,
          color: const Color(0xFFF1F3F8),
          shadowLightColor: Colors.white,
          shadowDarkColor: const Color(0xFFD0D7E5),
          boxShape: neu.NeumorphicBoxShape.roundRect(BorderRadius.circular(14)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  _questTitleIconFor(categoryStyle.category),
                  size: 22,
                  color: Colors.black,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    quest.title,
                    textAlign: TextAlign.left,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1C2940),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Lv.$questLevel',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF1C2940),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$earnedExp EXP',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF7E899D),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (dueDate != null) ...[
              const SizedBox(height: 12),
              _QuestDueDateRow(dueDate: dueDate),
            ],
            if (quest.subtasks.isNotEmpty) ...[
              const SizedBox(height: 18),
              _QuestSubtaskSummary(quest: quest, onSelect: onSubtaskSelect),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuestDueDateRow extends StatelessWidget {
  const _QuestDueDateRow({required this.dueDate});

  final DateTime dueDate;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.event_available_rounded,
          size: 16,
          color: Colors.blueGrey,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            formatQuestDueDate(dueDate),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF5E6678),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

class _QuestSubtaskSummary extends StatelessWidget {
  const _QuestSubtaskSummary({required this.quest, this.onSelect});

  final QuestItem quest;
  final ValueChanged<String>? onSelect;

  @override
  Widget build(BuildContext context) {
    final subtasks = quest.subtasks;
    final activeSubtaskId = quest.effectiveActiveSubtaskId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '세부 단계',
          style: TextStyle(
            color: Color(0xFF5E6678),
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 10),
        for (final subtask in subtasks) ...[
          Builder(
            builder: (context) {
              final isActive = subtask.id == activeSubtaskId;
              final progress = _questSubtaskProgress(subtask);
              final canSelect = onSelect != null && !subtask.isDone;
              return Semantics(
                button: canSelect,
                checked: subtask.isDone,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: canSelect ? () => onSelect!(subtask.id) : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Icon(
                            _questSubtaskIconFor(subtask, isActive: isActive),
                            size: 16,
                            color: _questSubtaskIconColorFor(
                              subtask,
                              isActive: isActive,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                subtask.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: subtask.isDone
                                      ? const Color(0xFF8B94A7)
                                      : const Color(0xFF253047),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                  decoration: subtask.isDone
                                      ? TextDecoration.lineThrough
                                      : TextDecoration.none,
                                  decorationColor: const Color(0xFF8B94A7),
                                ),
                              ),
                              const SizedBox(height: 5),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  value: progress,
                                  minHeight: 4,
                                  color: subtask.isDone
                                      ? const Color(0xFF38A169)
                                      : isActive
                                      ? const Color(0xFF6F63FF)
                                      : const Color(0xFFAAB3C3),
                                  backgroundColor: const Color(0xFFE1E6EF),
                                ),
                              ),
                              if (_questSubtaskMeta(
                                subtask,
                                isActive: isActive,
                              ).isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  _questSubtaskMeta(
                                    subtask,
                                    isActive: isActive,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: subtask.isDone
                                        ? const Color(0xFF9CA4B2)
                                        : isActive
                                        ? const Color(0xFF6F63FF)
                                        : const Color(0xFF7E899D),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          if (subtask != subtasks.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

String _questSubtaskMeta(QuestSubtask subtask, {required bool isActive}) {
  final parts = [
    if (subtask.isDone)
      '완료됨'
    else if (isActive)
      '진행 중'
    else if (subtask.isNextAction)
      '다음 행동'
    else
      '대기',
    '${_formatSubtaskDuration(subtask.clampedElapsedSeconds)}'
        '/${_formatSubtaskDuration(subtask.plannedDurationSeconds)}',
    if (subtask.energyRequired != null)
      _questSubtaskEnergyLabel(subtask.energyRequired!),
  ];
  return parts.join(' · ');
}

double _questSubtaskProgress(QuestSubtask subtask) {
  final plannedDurationSeconds = subtask.plannedDurationSeconds;
  if (plannedDurationSeconds <= 0) {
    return subtask.isDone ? 1 : 0;
  }
  return (subtask.clampedElapsedSeconds / plannedDurationSeconds).clamp(0, 1);
}

String _formatSubtaskDuration(int seconds) {
  final minutes = seconds ~/ 60;
  final remainingSeconds = seconds % 60;
  return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
}

IconData _questSubtaskIconFor(QuestSubtask subtask, {required bool isActive}) {
  if (subtask.isDone) {
    return Icons.check_circle_rounded;
  }
  if (isActive) {
    return Icons.play_circle_fill_rounded;
  }
  return Icons.radio_button_unchecked_rounded;
}

Color _questSubtaskIconColorFor(
  QuestSubtask subtask, {
  required bool isActive,
}) {
  if (subtask.isDone) {
    return const Color(0xFF38A169);
  }
  if (isActive) {
    return const Color(0xFF6F63FF);
  }
  return const Color(0xFF9BA4B6);
}

String _questSubtaskEnergyLabel(String energy) {
  return switch (energy) {
    'low' => '낮은 에너지',
    'high' => '높은 에너지',
    _ => '보통 에너지',
  };
}

int _questDifficultyLevel(String difficulty) {
  return switch (normalizeQuestDifficulty(difficulty)) {
    '쉬움' => 1,
    '보통' => 2,
    _ => 3,
  };
}

IconData _questTitleIconFor(String category) {
  return switch (category) {
    'work' => Icons.laptop_mac_rounded,
    'life' => Icons.flag_rounded,
    'study' => Icons.school_rounded,
    'home' => Icons.home_rounded,
    _ => Icons.task_alt_rounded,
  };
}

// 퀘스트 난이도, 보상, 카테고리 같은 요약 정보를 공통 칩으로 표시한다.
class QuestTimerInfoChip extends StatelessWidget {
  const QuestTimerInfoChip({
    super.key,
    required this.icon,
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final Color backgroundColor;
  final Color foregroundColor;

  @override
  Widget build(BuildContext context) {
    return neu.Neumorphic(
      style: neu.NeumorphicStyle(
        depth: 5,
        intensity: 0.88,
        surfaceIntensity: 0.18,
        color: backgroundColor,
        shadowLightColor: Colors.white.withValues(alpha: 0.98),
        shadowDarkColor: foregroundColor.withValues(alpha: 0.18),
        boxShape: const neu.NeumorphicBoxShape.stadium(),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foregroundColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }
}
