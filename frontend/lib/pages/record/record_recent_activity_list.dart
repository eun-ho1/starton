import 'package:flutter/material.dart';
import 'package:start_on/models/app_local_data.dart';
import 'package:start_on/pages/record/record_empty_card.dart';
import 'package:start_on/pages/record/record_recent_record_card.dart';

class RecordRecentActivityList extends StatelessWidget {
  const RecordRecentActivityList({
    super.key,
    required this.records,
    required this.onUndoCompletedQuest,
  });

  final List<CompletedQuestRecord> records;
  final ValueChanged<CompletedQuestRecord> onUndoCompletedQuest;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const RecordEmptyCard();
    }

    return Column(
      children: [
        for (var index = 0; index < records.length; index++) ...[
          RecordRecentRecordCard(
            record: records[index],
            onUndo: () => onUndoCompletedQuest(records[index]),
          ),
          if (index != records.length - 1) const SizedBox(height: 12),
        ],
      ],
    );
  }
}
