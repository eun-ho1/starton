import 'package:flutter/material.dart';
import 'package:start_on/models/app_local_data.dart';
import 'package:start_on/models/leaderboard_api_models.dart';
import 'package:start_on/widgets/common.dart';

class RankingScreen extends StatelessWidget {
  const RankingScreen({super.key, required this.data, this.leaderboard});

  final AppLocalData data;
  final LeaderboardResponse? leaderboard;

  @override
  Widget build(BuildContext context) {
    final localScore = _rankingScore(data);
    final entries = _leaderboardEntries(
      data,
      localScore,
      leaderboard: leaderboard,
    );
    final currentEntryIndex = entries.indexWhere(
      (entry) => entry.isCurrentUser,
    );
    final currentEntry = currentEntryIndex >= 0
        ? entries[currentEntryIndex]
        : null;
    final score = currentEntry?.score ?? localScore;
    final currentRank =
        currentEntry?.rank ??
        leaderboard?.currentUserRank ??
        currentEntryIndex + 1;
    final safeRank = currentRank <= 0 ? entries.length : currentRank;
    final nextEntry = currentEntryIndex > 0
        ? entries[currentEntryIndex - 1]
        : null;
    final nextScore = nextEntry?.score;
    final pointsToNext = nextScore == null
        ? 0
        : (nextScore - score + 1).clamp(0, nextScore);

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 120),
      children: [
        _RankingHeroCard(
          rank: safeRank,
          totalCount: entries.length,
          score: score,
          pointsToNext: pointsToNext,
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _RankingMetricCard(
                icon: Icons.task_alt_rounded,
                label: '완료한 퀘스트',
                value: '${data.completedQuestCount}',
                color: const Color(0xFFFF7F88),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _RankingMetricCard(
                icon: Icons.bolt_rounded,
                label: '획득한 EXP',
                value: '${data.earnedExp}',
                color: const Color(0xFF6F63FF),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const SectionHeading(icon: Icons.emoji_events_outlined, title: '주간 랭킹'),
        const SizedBox(height: 14),
        for (var index = 0; index < entries.length; index++) ...[
          _RankingRow(entry: entries[index]),
          if (index != entries.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _RankingHeroCard extends StatefulWidget {
  const _RankingHeroCard({
    required this.rank,
    required this.totalCount,
    required this.score,
    required this.pointsToNext,
  });

  final int rank;
  final int totalCount;
  final int score;
  final int pointsToNext;

  @override
  State<_RankingHeroCard> createState() => _RankingHeroCardState();
}

class _RankingHeroCardState extends State<_RankingHeroCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _gradientController;

  @override
  void initState() {
    super.initState();
    _gradientController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _gradientController.dispose();
    super.dispose();
  }

  double _lightOpacity(double cycle, double start) {
    final phase = (cycle - start) % 1.0;
    if (phase < 0.16) {
      return Curves.easeOutCubic.transform(phase / 0.16);
    }
    if (phase < 0.36) {
      return 1.0;
    }
    if (phase < 0.58) {
      return 1.0 - Curves.easeInCubic.transform((phase - 0.36) / 0.22);
    }
    return 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.totalCount <= 1
        ? 1.0
        : (widget.totalCount - widget.rank + 1) / widget.totalCount;
    const borderRadius = BorderRadius.all(Radius.circular(24));

    return Container(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6F63FF).withValues(alpha: 0.2),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: AnimatedBuilder(
          animation: _gradientController,
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.workspace_premium_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        "${widget.score} pt",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  "#${widget.rank}",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.pointsToNext == 0
                      ? "현재 1위입니다"
                      : "다음 순위까지 ${widget.pointsToNext}점 남았어요",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress.clamp(0.0, 1.0),
                    minHeight: 8,
                    backgroundColor: Colors.white.withValues(alpha: 0.28),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          builder: (context, child) {
            final cycle = _gradientController.value;
            final topLeftOpacity = _lightOpacity(cycle, 0.92);
            final bottomRightOpacity = _lightOpacity(cycle, 0.42);

            return DecoratedBox(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF5B4BE8),
                    Color(0xFF6F63FF),
                    Color(0xFF4F8DF7),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.78, -0.82),
                    radius: 0.92,
                    colors: [
                      Colors.white.withValues(alpha: 0.58 * topLeftOpacity),
                      Colors.white.withValues(alpha: 0.24 * topLeftOpacity),
                      Colors.white.withValues(alpha: 0),
                    ],
                    stops: const [0.0, 0.38, 1.0],
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: const Alignment(0.78, 0.82),
                      radius: 0.92,
                      colors: [
                        Colors.white.withValues(
                          alpha: 0.58 * bottomRightOpacity,
                        ),
                        Colors.white.withValues(
                          alpha: 0.24 * bottomRightOpacity,
                        ),
                        Colors.white.withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.38, 1.0],
                    ),
                  ),
                  child: child,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _RankingMetricCard extends StatelessWidget {
  const _RankingMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return NeumorphicRoundedCard(
      padding: const EdgeInsets.all(16),
      color: const Color(0xFFF1F3F8),
      depth: 6,
      intensity: 0.9,
      surfaceIntensity: 0.3,
      shadowLightColor: Colors.white,
      shadowDarkColor: const Color(0xFFD0D7E5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF1C2940),
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF7B8290),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingRow extends StatelessWidget {
  const _RankingRow({required this.entry});

  final _RankingEntry entry;

  @override
  Widget build(BuildContext context) {
    final textColor = entry.isCurrentUser
        ? const Color(0xFF211B70)
        : const Color(0xFF1C2940);
    return NeumorphicRoundedCard(
      padding: const EdgeInsets.all(14),
      color: const Color(0xFFF1F3F8),
      depth: 5,
      intensity: 0.86,
      surfaceIntensity: 0.28,
      borderRadius: 20,
      shadowLightColor: Colors.white,
      shadowDarkColor: const Color(0xFFD0D7E5),
      child: Row(
        children: [
          SizedBox(
            width: 32,
            child: Text(
              '${entry.rank}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: textColor,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: entry.color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(entry.icon, color: entry.color, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF7B8290),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${entry.score} pt',
            style: TextStyle(
              color: textColor,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingEntry {
  const _RankingEntry({
    required this.rank,
    required this.name,
    required this.subtitle,
    required this.score,
    required this.color,
    required this.icon,
    this.isCurrentUser = false,
  });

  final int rank;
  final String name;
  final String subtitle;
  final int score;
  final Color color;
  final IconData icon;
  final bool isCurrentUser;
}

int _rankingScore(AppLocalData data) {
  return data.earnedExp +
      data.credits * 2 +
      data.completedQuestCount * 80 +
      data.weeklyCompletedCount * 120 +
      data.weeklyCompletionRate * 8 +
      data.clearedDungeonIds.length * 240;
}

List<_RankingEntry> _leaderboardEntries(
  AppLocalData data,
  int score, {
  LeaderboardResponse? leaderboard,
}) {
  final serverEntries =
      leaderboard?.entries ?? const <LeaderboardEntryResponse>[];
  if (serverEntries.isNotEmpty) {
    return serverEntries
        .map(
          (entry) => _RankingEntry(
            rank: entry.rank,
            name: entry.userName,
            subtitle:
                'Lv.${entry.level} · 이번 주 ${entry.weeklyCompletedCount}개 완료',
            score: entry.score,
            color: entry.isCurrentUser
                ? const Color(0xFFFFB84D)
                : _colorForRankEntry(entry),
            icon: entry.isCurrentUser
                ? Icons.person_rounded
                : _iconForRankEntry(entry),
            isCurrentUser: entry.isCurrentUser,
          ),
        )
        .toList();
  }

  return [
    _RankingEntry(
      rank: 1,
      name: data.userName,
      subtitle: 'Lv.${data.level} · 이번 주 ${data.weeklyCompletedCount}개 완료',
      score: score,
      color: const Color(0xFFFFB84D),
      icon: Icons.person_rounded,
      isCurrentUser: true,
    ),
  ];
}

Color _colorForRankEntry(LeaderboardEntryResponse entry) {
  if (entry.weeklyCompletionRate >= 90) {
    return const Color(0xFFFF7F88);
  }
  if (entry.weeklyCompletedCount >= 10) {
    return const Color(0xFF6F63FF);
  }
  if (entry.clearedDungeonCount > 0) {
    return const Color(0xFF2EB67D);
  }
  return const Color(0xFF4BA3FF);
}

IconData _iconForRankEntry(LeaderboardEntryResponse entry) {
  if (entry.weeklyCompletionRate >= 90) {
    return Icons.local_fire_department_rounded;
  }
  if (entry.weeklyCompletedCount >= 10) {
    return Icons.psychology_alt_rounded;
  }
  if (entry.clearedDungeonCount > 0) {
    return Icons.workspace_premium_rounded;
  }
  return Icons.trending_up_rounded;
}
