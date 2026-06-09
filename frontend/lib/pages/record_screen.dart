import 'package:flutter/material.dart';
import 'package:start_on/models/app_local_data.dart';
import 'package:start_on/pages/record/record_sections.dart';
import 'package:start_on/widgets/common.dart';

class RecordScreen extends StatelessWidget {
  const RecordScreen({
    super.key,
    required this.data,
    required this.onUndoCompletedQuest,
  });

  final AppLocalData data;
  final ValueChanged<CompletedQuestRecord> onUndoCompletedQuest;

  @override
  Widget build(BuildContext context) {
    final completedRecords = data.completedQuests;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F8),
      body: Container(
        decoration: const BoxDecoration(color: Color(0xFFF1F3F8)),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 32),
            children: [
              RecordHeader(onBack: () => Navigator.of(context).pop()),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: RecordSummaryCard(
                      bgColor: const Color(0xFFFF7F88),
                      title: '전체 완료',
                      value: '${data.completedQuestCount}',
                      subtitle: '누적 완료 퀘스트',
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: RecordSummaryCard(
                      bgColor: const Color(0xFFAED7FF),
                      title: '이번 주',
                      value: '${data.weeklyCompletedCount}',
                      subtitle: '완료한 퀘스트',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              RecordSummaryCard(
                bgColor: const Color(0xFF8D7CFF),
                title: '달성률',
                value: '${data.weeklyCompletionRate}%',
                subtitle:
                    '지난 주 대비 ${data.weeklyRateDelta >= 0 ? '+' : ''}${data.weeklyRateDelta}%',
              ),
              const SizedBox(height: 22),
              RecordActivityChartCard(data: data),
              const SizedBox(height: 22),
              const SectionHeading(
                icon: Icons.emoji_events_outlined,
                title: '최근 활동',
              ),
              const SizedBox(height: 14),
              RecordRecentActivityList(
                records: completedRecords,
                onUndoCompletedQuest: onUndoCompletedQuest,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
