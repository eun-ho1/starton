import 'package:flutter/material.dart';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart' as neu;
import 'package:start_on/models/app_local_data.dart';

// 진행 중인 퀘스트 하나를 요약해서 보여주는 카드입니다.
class HomeQuestCard extends StatelessWidget {
  const HomeQuestCard({
    super.key,
    required this.quest,
    required this.onTap,
    required this.onDelete,
    this.selectable = false,
    this.selected = false,
  });

  final QuestItem quest;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final bool selectable;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final categoryStyle = _categoryStyleFor(quest.category);
    final categoryLabel = questCategoryLabel(quest.category).toUpperCase();
    final elapsedLabel = _formatElapsedSeconds(quest.elapsedSeconds);
    final difficultyLevel = _questDifficultyLevel(quest.difficulty);

    return neu.Neumorphic(
      style: neu.NeumorphicStyle(
        depth: 8,
        intensity: 0.82,
        surfaceIntensity: 0.28,
        color: const Color(0xFFF1F3F8),
        shadowLightColor: Colors.white,
        shadowDarkColor: const Color(0xFFD0D7E5),
        boxShape: neu.NeumorphicBoxShape.roundRect(BorderRadius.circular(14)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 17, 16, 15),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              quest.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF111318),
                                height: 1.1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (selectable)
                            _QuestSelectionMarker(selected: selected)
                          else
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: IconButton(
                                onPressed: onDelete,
                                icon: const Icon(Icons.close_rounded),
                                color: const Color(0xFFC1C6D0),
                                iconSize: 16,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints.tightFor(
                                  width: 24,
                                  height: 24,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 11),
                      Wrap(
                        spacing: 10,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: categoryStyle.backgroundColor,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              categoryLabel,
                              style: const TextStyle(
                                color: Color(0xFF111318),
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          Text(
                            elapsedLabel,
                            style: const TextStyle(
                              color: Color(0xFF8F949E),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          if (quest.dueDate != null)
                            Text(
                              formatQuestDueDate(quest.dueDate!),
                              style: const TextStyle(
                                color: Color(0xFF8F949E),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Lv.$difficultyLevel',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF33415C),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${quest.exp} EXP',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF98A2B3),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                if (!selectable)
                  GestureDetector(
                    onTap: onTap,
                    child: Container(
                      width: 31,
                      height: 31,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFFD7D1FF),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF6F63FF,
                            ).withValues(alpha: 0.22),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        color: Color(0xFF111318),
                        size: 22,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuestSelectionMarker extends StatelessWidget {
  const _QuestSelectionMarker({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? const Color(0xFF6F63FF) : const Color(0xFFE3E8F2),
        border: Border.all(
          color: selected ? const Color(0xFF6F63FF) : const Color(0xFFC8D0DF),
          width: 1.5,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
          : null,
    );
  }
}

String _formatElapsedSeconds(int elapsedSeconds) {
  final hours = (elapsedSeconds ~/ 3600).toString().padLeft(2, '0');
  final minutes = ((elapsedSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
  return '$hours:$minutes';
}

int _questDifficultyLevel(String difficulty) {
  return switch (normalizeQuestDifficulty(difficulty)) {
    '쉬움' => 1,
    '보통' => 2,
    _ => 3,
  };
}

_HomeQuestCategoryStyle _categoryStyleFor(String category) {
  final style = questCategoryStyleFor(category);
  return _HomeQuestCategoryStyle(
    backgroundColor: _softPillColorFor(style.category),
  );
}

Color _softPillColorFor(String category) {
  return switch (category) {
    'work' => const Color(0xFF63ADA8).withValues(alpha: 0.36),
    'life' => const Color(0xFFA8BFAA).withValues(alpha: 0.46),
    'study' => const Color(0xFFFFD954).withValues(alpha: 0.72),
    'home' => const Color(0xFFF79685).withValues(alpha: 0.82),
    _ => const Color(0xFFE6EAF2),
  };
}

class _HomeQuestCategoryStyle {
  const _HomeQuestCategoryStyle({required this.backgroundColor});

  final Color backgroundColor;
}
