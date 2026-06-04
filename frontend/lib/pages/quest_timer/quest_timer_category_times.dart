import 'package:flutter/material.dart';
import 'package:start_on/models/quest_category.dart';

class QuestTimerCategoryTimes extends StatelessWidget {
  const QuestTimerCategoryTimes({
    super.key,
    required this.category,
    required this.elapsedSeconds,
    required this.formatDuration,
    this.compact = false,
  });

  final String category;
  final int elapsedSeconds;
  final String Function(Duration duration) formatDuration;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final normalizedCategory = normalizeQuestCategory(category);
    final items = [
      _CategoryTimeItem(
        category: 'life',
        label: 'LIFE',
        icon: Icons.flag_rounded,
        color: const Color(0xFFA8BFAA),
      ),
      _CategoryTimeItem(
        category: 'work',
        label: 'WORK',
        icon: Icons.work_rounded,
        color: const Color(0xFF68B3AD),
      ),
      _CategoryTimeItem(
        category: 'study',
        label: 'SCHOOL',
        icon: Icons.school_rounded,
        color: const Color(0xFFFFD954),
      ),
      _CategoryTimeItem(
        category: 'home',
        label: 'HOME',
        icon: Icons.home_rounded,
        color: const Color(0xFFF79685),
      ),
    ];

    return Column(
      children: [
        for (var index = 0; index < items.length; index++) ...[
          _CategoryTimeBar(
            item: items[index],
            timeLabel: items[index].category == normalizedCategory
                ? formatDuration(Duration(seconds: elapsedSeconds))
                : '00:00:00',
            compact: compact,
          ),
          if (index != items.length - 1) SizedBox(height: compact ? 7 : 12),
        ],
      ],
    );
  }
}

class _CategoryTimeBar extends StatelessWidget {
  const _CategoryTimeBar({
    required this.item,
    required this.timeLabel,
    required this.compact,
  });

  final _CategoryTimeItem item;
  final String timeLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey<String>('quest_timer.category_bar.${item.category}'),
      height: compact ? 30 : 38,
      padding: EdgeInsets.symmetric(horizontal: compact ? 11 : 20),
      decoration: BoxDecoration(
        color: item.color,
        borderRadius: BorderRadius.circular(compact ? 11 : 14),
        boxShadow: [
          BoxShadow(
            color: item.color.withValues(alpha: 0.34),
            blurRadius: compact ? 8 : 12,
            offset: Offset(0, compact ? 4 : 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(item.icon, size: compact ? 15 : 18, color: Colors.black),
          SizedBox(width: compact ? 8 : 18),
          Expanded(
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 12 : 15,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
          ),
          SizedBox(width: compact ? 6 : 12),
          Text(
            timeLabel,
            style: TextStyle(
              fontSize: compact ? 10 : 12,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF8C919A),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryTimeItem {
  const _CategoryTimeItem({
    required this.category,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String category;
  final String label;
  final IconData icon;
  final Color color;
}
