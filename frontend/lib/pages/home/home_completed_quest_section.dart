import 'package:flutter/material.dart';
import 'package:start_on/models/app_local_data.dart';
import 'package:start_on/pages/home/home_completed_quest_card.dart';

// 오늘 완료된 퀘스트가 있을 때만 완료 기록 섹션을 노출합니다.
class HomeCompletedQuestSection extends StatelessWidget {
  const HomeCompletedQuestSection({super.key, required this.records});

  final List<CompletedQuestRecord> records;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '완료된 퀘스트',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1C2940),
            ),
          ),
          const SizedBox(height: 12),
          for (var index = 0; index < records.length; index++) ...[
            HomeCompletedQuestCard(record: records[index]),
            if (index != records.length - 1) const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
