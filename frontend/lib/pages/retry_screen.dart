import 'package:flutter/material.dart';
import 'package:start_on/models/quest_category.dart';
import 'package:start_on/models/quest_item.dart';
import 'package:start_on/widgets/common.dart';

enum _RetrySortMode { progress, easy, remaining }

class RetryScreen extends StatefulWidget {
  const RetryScreen({
    super.key,
    required this.quests,
    required this.onQuestStart,
    required this.onSkipToday,
  });

  final List<QuestItem> quests;
  final ValueChanged<QuestItem> onQuestStart;
  final VoidCallback onSkipToday;

  @override
  State<RetryScreen> createState() => _RetryScreenState();
}

class _RetryScreenState extends State<RetryScreen> {
  _RetrySortMode _sortMode = _RetrySortMode.progress;

  @override
  Widget build(BuildContext context) {
    final quests = _sortedQuests;
    final firstQuest = quests.isEmpty ? null : quests.first;

    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          children: [
            const _RetryHeader(),
            const SizedBox(height: 18),
            _RetrySummaryCard(count: quests.length),
            const SizedBox(height: 16),
            _RetrySortChips(
              selectedMode: _sortMode,
              onModeChanged: (mode) => setState(() => _sortMode = mode),
            ),
            const SizedBox(height: 26),
            if (quests.isEmpty)
              const _RetryEmptyCard()
            else
              for (final quest in quests) ...[
                _RetryQuestCard(
                  quest: quest,
                  onStart: () => widget.onQuestStart(quest),
                ),
                const SizedBox(height: 8),
              ],
          ],
        ),
        Positioned(
          left: 28,
          right: 28,
          bottom: 8,
          child: _RetryActions(
            enabled: firstQuest != null,
            onStart: firstQuest == null
                ? null
                : () => widget.onQuestStart(firstQuest),
            onSkipToday: firstQuest == null ? null : widget.onSkipToday,
          ),
        ),
      ],
    );
  }

  List<QuestItem> get _sortedQuests {
    final quests = [...widget.quests];
    quests.sort((a, b) {
      final primary = switch (_sortMode) {
        _RetrySortMode.progress => _progressFor(b).compareTo(_progressFor(a)),
        _RetrySortMode.easy => _difficultyRank(
          a.difficulty,
        ).compareTo(_difficultyRank(b.difficulty)),
        _RetrySortMode.remaining => _remainingSeconds(
          a,
        ).compareTo(_remainingSeconds(b)),
      };
      if (primary != 0) {
        return primary;
      }
      return a.title.compareTo(b.title);
    });
    return quests;
  }
}

class _RetryHeader extends StatelessWidget {
  const _RetryHeader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '리도전',
          style: TextStyle(
            color: Colors.black,
            fontSize: 28,
            fontWeight: FontWeight.w500,
            height: 1.14,
          ),
        ),
        SizedBox(height: 6),
        Text(
          '어제 멈춘 퀘스트를 오늘 다시 시작해보세요',
          style: TextStyle(
            color: Color(0xFF424242),
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        ),
      ],
    );
  }
}

class _RetrySummaryCard extends StatelessWidget {
  const _RetrySummaryCard({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return NeumorphicRoundedCard(
      padding: EdgeInsets.zero,
      color: const Color(0xFFF1F3F6),
      borderRadius: 24,
      depth: 7,
      intensity: 0.82,
      surfaceIntensity: 0.16,
      shadowDarkColor: const Color(0xFFD7DCE7),
      shadowLightColor: Colors.white,
      child: SizedBox(
        height: 74,
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 22, right: 12),
                child: Row(
                  children: [
                    const _RetrySummaryIcon(),
                    const SizedBox(width: 15),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '남은 퀘스트',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '$count',
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w900,
                                    height: 1,
                                  ),
                                ),
                                const TextSpan(
                                  text: ' 개',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    height: 1,
                                  ),
                                ),
                              ],
                            ),
                            style: const TextStyle(color: Colors.black),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(width: 1, height: 42, color: const Color(0xFFE3E5EC)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 20, right: 18),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _RetryPill(),
                    const SizedBox(height: 8),
                    Text(
                      count == 0 ? '오늘은 쉬어가도 괜찮아요' : '오늘은 가볍게 시작하기',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RetrySummaryIcon extends StatelessWidget {
  const _RetrySummaryIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image.asset(
          'web/icons/Icon-192.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.apps_rounded, size: 20, color: Colors.black),
        ),
      ),
    );
  }
}

class _RetryPill extends StatelessWidget {
  const _RetryPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 47,
      height: 15,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: const LinearGradient(
          colors: [Color(0xFF6C63FF), Color(0xFF5D9DFF)],
        ),
      ),
      child: const Text(
        'RETRY',
        style: TextStyle(
          color: Colors.white,
          fontSize: 8,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _RetrySortChips extends StatelessWidget {
  const _RetrySortChips({
    required this.selectedMode,
    required this.onModeChanged,
  });

  final _RetrySortMode selectedMode;
  final ValueChanged<_RetrySortMode> onModeChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RetrySortChip(
            icon: Icons.trending_up_rounded,
            label: '진행률 순',
            selected: selectedMode == _RetrySortMode.progress,
            onTap: () => onModeChanged(_RetrySortMode.progress),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _RetrySortChip(
            icon: Icons.flash_on_rounded,
            label: '쉬운 것부터',
            selected: selectedMode == _RetrySortMode.easy,
            onTap: () => onModeChanged(_RetrySortMode.easy),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _RetrySortChip(
            icon: Icons.timer_outlined,
            label: '남은 시간 적은 순',
            selected: selectedMode == _RetrySortMode.remaining,
            onTap: () => onModeChanged(_RetrySortMode.remaining),
          ),
        ),
      ],
    );
  }
}

class _RetrySortChip extends StatelessWidget {
  const _RetrySortChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final child = SizedBox(
      height: 42,
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.black),
            const SizedBox(width: 4),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: selected
          ? NeumorphicRoundedCard(
              padding: EdgeInsets.zero,
              color: const Color(0xFFF1F3F6),
              borderRadius: 12,
              depth: 5,
              intensity: 0.78,
              surfaceIntensity: 0.14,
              shadowDarkColor: const Color(0xFFD8DDE8),
              shadowLightColor: Colors.white,
              child: child,
            )
          : child,
    );
  }
}

class _RetryQuestCard extends StatelessWidget {
  const _RetryQuestCard({required this.quest, required this.onStart});

  final QuestItem quest;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final categoryStyle = questCategoryStyleFor(quest.category);
    final difficulty = normalizeQuestDifficulty(quest.difficulty);
    final progress = _progressFor(quest);
    final progressText = '${(progress * 100).round()}%';

    return GestureDetector(
      onTap: onStart,
      behavior: HitTestBehavior.opaque,
      child: NeumorphicRoundedCard(
        padding: EdgeInsets.zero,
        color: const Color(0xFFF1F3F6),
        borderRadius: 20,
        depth: 7,
        intensity: 0.82,
        surfaceIntensity: 0.16,
        shadowDarkColor: const Color(0xFFD7DCE7),
        shadowLightColor: Colors.white,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              const SizedBox(width: 15),
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: categoryStyle.backgroundColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(categoryStyle.icon, size: 16, color: Colors.black),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quest.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.black,
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text:
                                  '예상 ${_formatDuration(quest.effectiveDurationSeconds)} · 난이도 ',
                            ),
                            TextSpan(
                              text: difficulty,
                              style: TextStyle(
                                color: categoryStyle.accentColor,
                              ),
                            ),
                            const TextSpan(text: ' · 진행 '),
                            TextSpan(
                              text: progressText,
                              style: TextStyle(
                                color: categoryStyle.accentColor,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF8E8E93),
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          height: 1,
                        ),
                      ),
                      const SizedBox(height: 5),
                      _RetryProgressBar(
                        progress: progress,
                        accentColor: categoryStyle.accentColor,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: Color(0xFFD4D4F8),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.black,
                  size: 22,
                ),
              ),
              const SizedBox(width: 25),
            ],
          ),
        ),
      ),
    );
  }
}

class _RetryEmptyCard extends StatelessWidget {
  const _RetryEmptyCard();

  @override
  Widget build(BuildContext context) {
    return NeumorphicRoundedCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      color: const Color(0xFFF1F3F6),
      borderRadius: 20,
      depth: 6,
      intensity: 0.78,
      surfaceIntensity: 0.14,
      shadowDarkColor: const Color(0xFFD8DDE8),
      shadowLightColor: Colors.white,
      child: const Text(
        '다시 시작할 퀘스트가 없어요.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xFF70727A),
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _RetryProgressBar extends StatelessWidget {
  const _RetryProgressBar({required this.progress, required this.accentColor});

  final double progress;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 155,
      height: 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: const Color(0xFFD9D9D9).withValues(alpha: 0.85),
          valueColor: AlwaysStoppedAnimation<Color>(accentColor),
        ),
      ),
    );
  }
}

class _RetryActions extends StatelessWidget {
  const _RetryActions({
    required this.enabled,
    required this.onStart,
    required this.onSkipToday,
  });

  final bool enabled;
  final VoidCallback? onStart;
  final VoidCallback? onSkipToday;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RetryActionButton(
          label: '다시 시작',
          filled: true,
          enabled: enabled,
          onTap: onStart,
        ),
        const SizedBox(height: 9),
        _RetryActionButton(
          label: '오늘은 건너뛰기',
          enabled: enabled,
          onTap: onSkipToday,
        ),
      ],
    );
  }
}

class _RetryActionButton extends StatelessWidget {
  const _RetryActionButton({
    required this.label,
    required this.enabled,
    this.filled = false,
    this.onTap,
  });

  final String label;
  final bool enabled;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: filled ? const Color(0xFFD4D4F8) : const Color(0xFFF1F3F6),
        borderRadius: BorderRadius.circular(16),
        border: filled
            ? null
            : Border.all(color: const Color(0xFFD4D4F8), width: 1.5),
        boxShadow: filled
            ? [
                BoxShadow(
                  color: const Color(0xFFBBC1D2).withValues(alpha: 0.42),
                  blurRadius: 14,
                  offset: const Offset(4, 6),
                ),
                BoxShadow(
                  color: Colors.white.withValues(alpha: 0.95),
                  blurRadius: 12,
                  offset: const Offset(-4, -5),
                ),
              ]
            : null,
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 15,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
    );

    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: content,
      ),
    );
  }
}

double _progressFor(QuestItem quest) {
  final duration = quest.effectiveDurationSeconds;
  if (duration <= 0) {
    return 0;
  }
  return (quest.elapsedSeconds / duration).clamp(0.0, 1.0).toDouble();
}

int _remainingSeconds(QuestItem quest) {
  final remaining = quest.effectiveDurationSeconds - quest.elapsedSeconds;
  return remaining < 0 ? 0 : remaining;
}

int _difficultyRank(String difficulty) {
  return switch (normalizeQuestDifficulty(difficulty)) {
    '쉬움' => 0,
    '보통' => 1,
    _ => 2,
  };
}

String _formatDuration(int seconds) {
  final minutes = (seconds / 60).ceil();
  if (minutes <= 0) {
    return '0분';
  }
  if (minutes < 60) {
    return '$minutes분';
  }

  final hours = minutes ~/ 60;
  final remainderMinutes = minutes % 60;
  if (remainderMinutes == 0) {
    return '$hours시간';
  }
  return '$hours시간 $remainderMinutes분';
}
