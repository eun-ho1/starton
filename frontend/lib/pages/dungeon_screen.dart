import 'package:flutter/material.dart';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart' as neu;
import 'package:start_on/models/dungeon_api_models.dart';
import 'package:start_on/widgets/common.dart';

class DungeonScreen extends StatelessWidget {
  const DungeonScreen({
    super.key,
    required this.dungeons,
    required this.credits,
    required this.onClearDungeon,
  });

  final List<DungeonStatusResponse> dungeons;
  final int credits;
  final ValueChanged<String> onClearDungeon;

  @override
  Widget build(BuildContext context) {
    final clearedCount = dungeons.where((item) => item.cleared).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 120),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                '던전',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1C2940),
                ),
              ),
            ),
            _DungeonCreditBadge(credits: credits),
          ],
        ),
        const SizedBox(height: 24),
        const SectionHeading(
          icon: Icons.workspace_premium_outlined,
          title: '내 퀘스트 던전',
        ),
        const SizedBox(height: 14),
        if (dungeons.isEmpty)
          const NeumorphicRoundedCard(
            padding: EdgeInsets.all(18),
            color: Color(0xFFF1F3F8),
            borderRadius: 22,
            depth: 6,
            intensity: 0.9,
            surfaceIntensity: 0.32,
            shadowDarkColor: Color(0xFFD0D7E5),
            shadowLightColor: Colors.white,
            child: Text(
              '표시할 퀘스트가 아직 없어요.',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF667085),
              ),
            ),
          ),
        for (final dungeon in dungeons) ...[
          DungeonCard(
            challenge: dungeon,
            onClear: () => onClearDungeon(dungeon.dungeonId),
          ),
          const SizedBox(height: 14),
        ],
        DungeonRewardCard(
          clearedCount: clearedCount,
          totalCount: dungeons.length,
          totalCreditReward: dungeons.fold(
            0,
            (sum, item) => sum + item.creditReward,
          ),
        ),
      ],
    );
  }
}

class _DungeonCreditBadge extends StatelessWidget {
  const _DungeonCreditBadge({required this.credits});

  final int credits;

  @override
  Widget build(BuildContext context) {
    return neu.Neumorphic(
      style: neu.NeumorphicStyle(
        depth: -3,
        intensity: 0.82,
        surfaceIntensity: 0.22,
        color: const Color(0xFFF1F3F8),
        shadowLightColor: Colors.white,
        shadowDarkColor: const Color(0xFFD0D7E5),
        boxShape: neu.NeumorphicBoxShape.roundRect(BorderRadius.circular(10)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.monetization_on_outlined,
            size: 17,
            color: Color(0xFF745C00),
          ),
          const SizedBox(width: 6),
          Text(
            '$credits',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1C2940),
            ),
          ),
        ],
      ),
    );
  }
}

class DungeonCard extends StatelessWidget {
  const DungeonCard({
    super.key,
    required this.challenge,
    required this.onClear,
  });

  final DungeonStatusResponse challenge;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final cleared = challenge.cleared;
    final canClaim = challenge.canClaim;

    return NeumorphicRoundedCard(
      padding: const EdgeInsets.all(18),
      color: const Color(0xFFF1F3F8),
      borderRadius: 22,
      depth: 6,
      intensity: 0.9,
      surfaceIntensity: 0.32,
      shadowDarkColor: const Color(0xFFD0D7E5),
      shadowLightColor: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  challenge.title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF463317),
                  ),
                ),
              ),
              neu.Neumorphic(
                style: neu.NeumorphicStyle(
                  depth: 5,
                  intensity: 0.88,
                  surfaceIntensity: 0.3,
                  color: const Color(0xFFF1F3F8),
                  shadowLightColor: Colors.white,
                  shadowDarkColor: const Color(0xFFD0D7E5),
                  boxShape: neu.NeumorphicBoxShape.roundRect(
                    BorderRadius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '+${challenge.creditReward}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF33415C),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.monetization_on_outlined,
                      size: 16,
                      color: Color(0xFF745C00),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            challenge.completed ? '퀘스트 완료' : '퀘스트 진행 중',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: challenge.completed
                  ? const Color(0xFF2E7D32)
                  : const Color(0xFF8B6F47),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '난이도 ${_difficultyLabel(challenge.difficulty)}',
            style: const TextStyle(fontSize: 14, color: Color(0xFF68553A)),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: neu.Neumorphic(
              style: neu.NeumorphicStyle(
                depth: cleared
                    ? -2
                    : canClaim
                    ? 5
                    : 2,
                intensity: 0.9,
                surfaceIntensity: 0.32,
                color: cleared
                    ? const Color(0xFFCFCBEA)
                    : canClaim
                    ? const Color(0xFF6F63FF)
                    : const Color(0xFFB7BFCE),
                shadowLightColor: Colors.white,
                shadowDarkColor: const Color(
                  0xFF4E46B8,
                ).withValues(alpha: 0.38),
                boxShape: neu.NeumorphicBoxShape.roundRect(
                  BorderRadius.circular(16),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: canClaim ? onClear : null,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: Text(
                        cleared
                            ? '보상 수령 완료'
                            : canClaim
                            ? '보상 수령하기'
                            : '퀘스트 완료 후 수령 가능',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DungeonRewardCard extends StatelessWidget {
  const DungeonRewardCard({
    super.key,
    required this.clearedCount,
    required this.totalCount,
    required this.totalCreditReward,
  });

  final int clearedCount;
  final int totalCount;
  final int totalCreditReward;

  @override
  Widget build(BuildContext context) {
    final progress = totalCount == 0 ? 0.0 : clearedCount / totalCount;

    return NeumorphicRoundedCard(
      padding: const EdgeInsets.all(20),
      color: const Color(0xFFF1F3F8),
      depth: 6,
      intensity: 0.9,
      surfaceIntensity: 0.32,
      shadowLightColor: Colors.white,
      shadowDarkColor: const Color(0xFFD0D7E5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: SectionHeading(
                  icon: Icons.workspace_premium_outlined,
                  title: '던전 보상',
                ),
              ),
              neu.Neumorphic(
                style: neu.NeumorphicStyle(
                  depth: 6,
                  intensity: 0.9,
                  surfaceIntensity: 0.3,
                  color: const Color(0xFFF1F3F8),
                  shadowLightColor: Colors.white,
                  shadowDarkColor: const Color(0xFFD0D7E5),
                  boxShape: neu.NeumorphicBoxShape.roundRect(
                    BorderRadius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.monetization_on_outlined,
                      size: 18,
                      color: Color(0xFF745C00),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '+$totalCreditReward',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF473200),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(999)),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: progress,
              backgroundColor: const Color(0xFFE8ECF3),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFFF8B93),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$clearedCount / $totalCount 보상 수령 완료',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF98A2B3),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String _difficultyLabel(String difficulty) {
  final normalized = difficulty.trim().toLowerCase();
  if (normalized == 'easy') {
    return '쉬움';
  }
  if (normalized == 'hard') {
    return '어려움';
  }
  return '보통';
}
