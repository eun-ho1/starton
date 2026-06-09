import 'package:flutter/material.dart';
import 'package:start_on/models/app_local_data.dart';
import 'package:start_on/widgets/common.dart';

class RecordRecentRecordCard extends StatelessWidget {
  const RecordRecentRecordCard({
    super.key,
    required this.record,
    required this.onUndo,
  });

  final CompletedQuestRecord record;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    final completedAt = DateTime.tryParse(record.completedAt)?.toLocal();
    final date = completedAt == null
        ? '완료 기록'
        : '${completedAt.year}.${completedAt.month.toString().padLeft(2, '0')}.${completedAt.day.toString().padLeft(2, '0')} '
            '${completedAt.hour.toString().padLeft(2, '0')}:${completedAt.minute.toString().padLeft(2, '0')}';

    return NeumorphicRoundedCard(
      padding: const EdgeInsets.all(18),
      color: const Color(0xFFF1F3F8),
      depth: 6,
      intensity: 0.9,
      surfaceIntensity: 0.32,
      shadowLightColor: Colors.white,
      shadowDarkColor: const Color(0xFFD0D7E5),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  date,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF33415C),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${record.title} 완료',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF7E899D),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '+${record.earnedExp}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFFF8B93),
                ),
              ),
              const Text(
                'EXP',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF98A2B3),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: '완료 취소',
            child: IconButton(
              onPressed: onUndo,
              icon: const Icon(Icons.undo_rounded),
              color: const Color(0xFF6F63FF),
              iconSize: 21,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            ),
          ),
        ],
      ),
    );
  }
}
