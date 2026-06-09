import 'package:flutter/material.dart';
import 'package:start_on/models/app_local_data.dart';
import 'package:start_on/pages/home/home_empty_quest_card.dart';
import 'package:start_on/pages/home/home_quest_card.dart';

// 퀘스트가 없으면 빈 상태 카드를, 있으면 개별 퀘스트 카드를 렌더링합니다.
class HomeQuestList extends StatelessWidget {
  const HomeQuestList({
    super.key,
    required this.quests,
    required this.onAddQuest,
    required this.onQuestTap,
    required this.onDeleteQuest,
    this.bulkDeleteMode = false,
    this.selectedQuestIds = const <String>{},
    this.onToggleQuestSelection,
  });

  final List<QuestItem> quests;
  final VoidCallback onAddQuest;
  final ValueChanged<QuestItem> onQuestTap;
  final ValueChanged<QuestItem> onDeleteQuest;
  final bool bulkDeleteMode;
  final Set<String> selectedQuestIds;
  final ValueChanged<QuestItem>? onToggleQuestSelection;

  @override
  Widget build(BuildContext context) {
    if (quests.isEmpty) {
      return HomeEmptyQuestCard(onTap: onAddQuest);
    }

    return Column(
      children: [
        for (var index = 0; index < quests.length; index++) ...[
          HomeQuestCard(
            quest: quests[index],
            onTap: bulkDeleteMode
                ? () => onToggleQuestSelection?.call(quests[index])
                : () => onQuestTap(quests[index]),
            onDelete: () => onDeleteQuest(quests[index]),
            selectable: bulkDeleteMode,
            selected: selectedQuestIds.contains(quests[index].id),
          ),
          if (index != quests.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}
