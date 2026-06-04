import 'package:flutter/material.dart';
import 'package:flutter_neumorphic_plus/flutter_neumorphic.dart' as neu;
import 'package:start_on/models/app_local_data.dart';

class HomeCategoryQuestDialog extends StatelessWidget {
  const HomeCategoryQuestDialog({
    required this.category,
    required this.quests,
    required this.completedRecords,
    super.key,
  });

  final String category;
  final List<QuestItem> quests;
  final List<CompletedQuestRecord> completedRecords;

  @override
  Widget build(BuildContext context) {
    final style = questCategoryStyleFor(category);
    final dialogBackgroundColor = _categoryDialogBackgroundColor(category);
    final totalCount = quests.length + completedRecords.length;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: ColoredBox(
          color: dialogBackgroundColor,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.76,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      neu.Neumorphic(
                        style: neu.NeumorphicStyle(
                          depth: 5,
                          intensity: 0.6,
                          surfaceIntensity: 0.24,
                          color: Color.alphaBlend(
                            style.accentColor.withValues(alpha: 0.08),
                            dialogBackgroundColor,
                          ),
                          shadowLightColor: Colors.white,
                          boxShape: neu.NeumorphicBoxShape.roundRect(
                            BorderRadius.circular(14),
                          ),
                        ),
                        padding: const EdgeInsets.all(10),
                        child: Icon(style.icon, color: style.accentColor),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              style.label,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.black,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${quests.length} 진행 중 · ${completedRecords.length} 완료',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF6C7A90),
                              ),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: neu.Neumorphic(
                          style: neu.NeumorphicStyle(
                            depth: 4,
                            intensity: 0.6,
                            surfaceIntensity: 0.18,
                            color: dialogBackgroundColor,
                            shadowLightColor: Colors.white,
                            boxShape: const neu.NeumorphicBoxShape.circle(),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFF93A1B5),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (totalCount == 0)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: SizedBox(
                        width: double.infinity,
                        child: Column(
                          children: [
                            Icon(
                              style.icon,
                              color: style.accentColor.withValues(alpha: 0.8),
                              size: 28,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '아직 ${style.label} 퀘스트가 없습니다',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF304056),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (quests.isNotEmpty) ...[
                          _CategoryDialogSectionLabel(
                            label: '진행 중',
                            accentColor: style.accentColor,
                          ),
                          const SizedBox(height: 10),
                          for (var i = 0; i < quests.length; i++) ...[
                            _CategoryQuestTile(
                              quest: quests[i],
                              accentColor: style.accentColor,
                              backgroundColor: dialogBackgroundColor,
                              onTap: () => Navigator.of(context).pop(quests[i]),
                            ),
                            if (i != quests.length - 1)
                              const SizedBox(height: 10),
                          ],
                        ],
                        if (quests.isNotEmpty && completedRecords.isNotEmpty)
                          const SizedBox(height: 18),
                        if (completedRecords.isNotEmpty) ...[
                          _CategoryDialogSectionLabel(
                            label: '완료',
                            accentColor: style.accentColor,
                          ),
                          const SizedBox(height: 10),
                          for (var i = 0; i < completedRecords.length; i++) ...[
                            _CompletedCategoryQuestTile(
                              record: completedRecords[i],
                              accentColor: style.accentColor,
                              backgroundColor: dialogBackgroundColor,
                            ),
                            if (i != completedRecords.length - 1)
                              const SizedBox(height: 10),
                          ],
                        ],
                      ],
                    ),
                  const SizedBox(height: 18),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop('add'),
                    child: neu.Neumorphic(
                      style: neu.NeumorphicStyle(
                        depth: 6,
                        intensity: 0.6,
                        surfaceIntensity: 0.22,
                        color: style.accentColor,
                        shadowLightColor: Colors.white,
                        boxShape: neu.NeumorphicBoxShape.roundRect(
                          BorderRadius.circular(18),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded, color: dialogBackgroundColor),
                          const SizedBox(width: 8),
                          Text(
                            '${style.label} 퀘스트 추가',
                            style: TextStyle(
                              color: dialogBackgroundColor,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryQuestTile extends StatelessWidget {
  const _CategoryQuestTile({
    required this.quest,
    required this.accentColor,
    required this.backgroundColor,
    required this.onTap,
  });

  final QuestItem quest;
  final Color accentColor;
  final Color backgroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final difficultyLabel = switch (quest.difficulty) {
      '보통' => '중간',
      _ => quest.difficulty,
    };
    final baseColor = Color.alphaBlend(
      accentColor.withValues(alpha: 0.08),
      backgroundColor,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: GestureDetector(
        onTap: onTap,
        child: neu.Neumorphic(
          style: neu.NeumorphicStyle(
            depth: 7,
            intensity: 0.5,
            surfaceIntensity: 0.24,
            color: baseColor,
            shadowLightColor: Colors.white,
            boxShape: neu.NeumorphicBoxShape.roundRect(
              BorderRadius.circular(18),
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quest.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF243248),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _CategoryDialogMetaChip(
                          label:
                              '$difficultyLabel:${quest.defaultDurationSeconds ~/ 60}분',
                          accentColor: accentColor,
                          backgroundColor: backgroundColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.chevron_right_rounded,
                color: accentColor.withValues(alpha: 0.76),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryDialogSectionLabel extends StatelessWidget {
  const _CategoryDialogSectionLabel({
    required this.label,
    required this.accentColor,
  });

  final String label;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: accentColor.withValues(alpha: 0.86),
      ),
    );
  }
}

class _CompletedCategoryQuestTile extends StatelessWidget {
  const _CompletedCategoryQuestTile({
    required this.record,
    required this.accentColor,
    required this.backgroundColor,
  });

  final CompletedQuestRecord record;
  final Color accentColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    final difficultyLabel = switch (record.difficulty) {
      '보통' => '중간',
      _ => record.difficulty,
    };
    final completedAt = DateTime.tryParse(record.completedAt)?.toLocal();
    final completedLabel = completedAt == null
        ? '완료'
        : '${completedAt.month}/${completedAt.day} 완료';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: neu.Neumorphic(
        style: neu.NeumorphicStyle(
          depth: 7,
          intensity: 0.92,
          surfaceIntensity: 0.28,
          color: Color.alphaBlend(
            accentColor.withValues(alpha: 0.2),
            backgroundColor,
          ),
          shadowLightColor: Colors.white,
          boxShape: neu.NeumorphicBoxShape.roundRect(BorderRadius.circular(18)),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF243248),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _CategoryDialogMetaChip(
                        label:
                            '$difficultyLabel:${record.elapsedSeconds ~/ 60}분',
                        accentColor: accentColor,
                        backgroundColor: backgroundColor,
                      ),
                      _CategoryDialogMetaChip(
                        label: completedLabel,
                        accentColor: accentColor,
                        backgroundColor: backgroundColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(
              Icons.check_circle_rounded,
              color: accentColor.withValues(alpha: 0.88),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryDialogMetaChip extends StatelessWidget {
  const _CategoryDialogMetaChip({
    required this.label,
    required this.accentColor,
    required this.backgroundColor,
  });

  final String label;
  final Color accentColor;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: accentColor,
      ),
    );
  }
}

Color _categoryDialogBackgroundColor(String category) {
  return switch (normalizeQuestCategory(category)) {
    'work' => const Color(0xFFEAF5F4),
    'life' => const Color(0xFFF0F7F1),
    'study' => const Color(0xFFFFF8E8),
    'home' => const Color(0xFFFFF4F0),
    _ => const Color(0xFFF1F3F8),
  };
}
