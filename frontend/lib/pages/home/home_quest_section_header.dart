import 'package:flutter/material.dart';
import 'package:start_on/models/app_local_data.dart';

class HomeQuestSectionHeader extends StatelessWidget {
  const HomeQuestSectionHeader({
    super.key,
    required this.questCount,
    required this.quests,
    required this.completedRecords,
  });

  final int questCount;
  final List<QuestItem> quests;
  final List<CompletedQuestRecord> completedRecords;

  void _openCalendar(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _HomeCalendarPage(
          quests: quests,
          completedRecords: completedRecords,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Flexible(
                  child: Text(
                    '오늘의 퀘스트',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF050608),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                _CalendarHeaderButton(onTap: () => _openCalendar(context)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CalendarHeaderButton extends StatelessWidget {
  const _CalendarHeaderButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '캘린더',
      child: Semantics(
        button: true,
        label: '캘린더 열기',
        child: GestureDetector(
          onTap: onTap,
          child: const SizedBox(
            width: 31,
            height: 31,
            child: Icon(
              Icons.calendar_today_rounded,
              size: 17,
              color: Color(0xFF1C2940),
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeCalendarPage extends StatefulWidget {
  const _HomeCalendarPage({
    required this.quests,
    required this.completedRecords,
  });

  final List<QuestItem> quests;
  final List<CompletedQuestRecord> completedRecords;

  @override
  State<_HomeCalendarPage> createState() => _HomeCalendarPageState();
}

class _HomeCalendarPageState extends State<_HomeCalendarPage> {
  late DateTime _selectedDate = _dateOnly(DateTime.now());
  late DateTime _focusedMonth = _monthOnly(_selectedDate);

  @override
  Widget build(BuildContext context) {
    final today = _dateOnly(DateTime.now());
    final selectedQuests = _questsForDate(widget.quests, _selectedDate);
    final todayQuests = _questsForDate(widget.quests, today);
    final upcomingQuests = _upcomingQuests(
      widget.quests,
      today,
    ).where((quest) => !_isSameDay(quest.dueDate!, _selectedDate)).toList();
    final monthQuestCount = _questsInMonth(widget.quests, _focusedMonth).length;
    final monthCompletedCount = _completedInMonth(
      widget.completedRecords,
      _focusedMonth,
    ).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F6),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
          children: [
            _CalendarTopBar(
              onBack: () => Navigator.of(context).pop(),
              onOpenBoard: _openCalendarBoard,
            ),
            const SizedBox(height: 18),
            _MonthCalendarCard(
              focusedMonth: _focusedMonth,
              selectedDate: _selectedDate,
              quests: widget.quests,
              completedRecords: widget.completedRecords,
              onPreviousMonth: () => _shiftMonth(-1),
              onNextMonth: () => _shiftMonth(1),
              onDaySelected: _selectDay,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _CalendarMetricCard(
                    label: 'MONTH',
                    value: '$monthQuestCount',
                    icon: Icons.event_note_rounded,
                    color: const Color(0xFF63ADA8),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CalendarMetricCard(
                    label: 'TODAY',
                    value: '${todayQuests.length}',
                    icon: Icons.today_rounded,
                    color: const Color(0xFFF39482),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CalendarMetricCard(
                    label: 'DONE',
                    value: '$monthCompletedCount',
                    icon: Icons.check_circle_rounded,
                    color: const Color(0xFF6F63FF),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _CalendarAgendaSection(
              title: _isSameDay(_selectedDate, today)
                  ? '오늘 일정'
                  : '${formatQuestDueDate(_selectedDate)} 일정',
              emptyText: _isSameDay(_selectedDate, today)
                  ? '오늘 마감인 퀘스트가 없어요.'
                  : '${formatQuestDueDate(_selectedDate)}에 마감인 퀘스트가 없어요.',
              quests: selectedQuests,
            ),
            const SizedBox(height: 18),
            _CalendarAgendaSection(
              title: '다가오는 일정',
              emptyText: '마감일이 있는 퀘스트가 없어요.',
              quests: upcomingQuests,
            ),
          ],
        ),
      ),
    );
  }

  void _shiftMonth(int offset) {
    setState(() {
      _focusedMonth = DateTime(
        _focusedMonth.year,
        _focusedMonth.month + offset,
      );
      if (_selectedDate.year != _focusedMonth.year ||
          _selectedDate.month != _focusedMonth.month) {
        _selectedDate = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
      }
    });
  }

  void _selectDay(DateTime day) {
    setState(() {
      _selectedDate = _dateOnly(day);
      _focusedMonth = _monthOnly(day);
    });
  }

  void _openCalendarBoard() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CalendarBoardPage(
          focusedMonth: _focusedMonth,
          quests: widget.quests,
          completedRecords: widget.completedRecords,
        ),
      ),
    );
  }
}

class _CalendarTopBar extends StatelessWidget {
  const _CalendarTopBar({required this.onBack, required this.onOpenBoard});

  final VoidCallback onBack;
  final VoidCallback onOpenBoard;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          tooltip: '뒤로',
          onTap: onBack,
        ),
        const Expanded(
          child: Center(
            child: Text(
              'CALENDAR',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF1C2940),
              ),
            ),
          ),
        ),
        _RoundIconButton(
          icon: Icons.calendar_month_rounded,
          tooltip: '연간 보기',
          onTap: onOpenBoard,
        ),
      ],
    );
  }
}

class _CalendarBoardPage extends StatelessWidget {
  const _CalendarBoardPage({
    required this.focusedMonth,
    required this.quests,
    required this.completedRecords,
  });

  final DateTime focusedMonth;
  final List<QuestItem> quests;
  final List<CompletedQuestRecord> completedRecords;

  @override
  Widget build(BuildContext context) {
    final yearStart = DateTime(focusedMonth.year);
    final months = [
      for (var index = 0; index < 12; index += 1)
        DateTime(yearStart.year, index + 1),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF1F3F6),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 30),
          children: [
            _CalendarBoardTopBar(
              year: focusedMonth.year,
              onBack: () => Navigator.of(context).pop(),
            ),
            const SizedBox(height: 16),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.86,
              ),
              itemCount: months.length,
              itemBuilder: (context, index) {
                final month = months[index];
                return _MultiMonthCalendarCard(
                  month: month,
                  isFocusedMonth: month.month == focusedMonth.month,
                  quests: quests,
                  completedRecords: completedRecords,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _CalendarBoardTopBar extends StatelessWidget {
  const _CalendarBoardTopBar({required this.year, required this.onBack});

  final int year;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundIconButton(
          icon: Icons.arrow_back_ios_new_rounded,
          tooltip: '뒤로',
          onTap: onBack,
        ),
        Expanded(
          child: Center(
            child: Text(
              '$year CALENDAR',
              style: const TextStyle(
                color: Color(0xFF1C2940),
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: const Icon(
            Icons.view_module_rounded,
            color: Color(0xFF1C2940),
            size: 19,
          ),
        ),
      ],
    );
  }
}

class _MultiMonthCalendarCard extends StatelessWidget {
  const _MultiMonthCalendarCard({
    required this.month,
    required this.isFocusedMonth,
    required this.quests,
    required this.completedRecords,
  });

  final DateTime month;
  final bool isFocusedMonth;
  final List<QuestItem> quests;
  final List<CompletedQuestRecord> completedRecords;

  @override
  Widget build(BuildContext context) {
    final days = _visibleCalendarDays(month);
    final monthQuestCount = _questsInMonth(quests, month).length;
    final monthCompletedCount = _completedInMonth(
      completedRecords,
      month,
    ).length;

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: isFocusedMonth ? const Color(0xFFFF8B93) : Colors.transparent,
          width: 1.4,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 14,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _shortMonthLabel(month),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1C2940),
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (monthQuestCount > 0 || monthCompletedCount > 0)
                Text(
                  '$monthQuestCount/$monthCompletedCount',
                  style: const TextStyle(
                    color: Color(0xFF9AA2B1),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              for (final label in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFFB0B6C2),
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
              ),
              itemCount: days.length,
              itemBuilder: (context, index) {
                final day = days[index];
                final hasQuest = _questsForDate(quests, day).isNotEmpty;
                final hasDone = _completedForDate(
                  completedRecords,
                  day,
                ).isNotEmpty;
                final isInMonth = day.month == month.month;
                final isToday = _isSameDay(day, DateTime.now());
                final backgroundColor = hasQuest
                    ? const Color(0xFFFF8B93)
                    : hasDone
                    ? const Color(0xFF6F63FF)
                    : isToday
                    ? const Color(0xFFFFE0E3)
                    : const Color(0xFFF1F3F6);
                final textColor = hasQuest || hasDone
                    ? Colors.white
                    : isInMonth
                    ? const Color(0xFF1C2940)
                    : const Color(0xFFC8CDD6);
                return Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isInMonth ? backgroundColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    '${day.day}',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 12,
                offset: Offset(0, 5),
              ),
            ],
          ),
          child: Icon(icon, size: 18, color: const Color(0xFF1C2940)),
        ),
      ),
    );
  }
}

class _MonthCalendarCard extends StatelessWidget {
  const _MonthCalendarCard({
    required this.focusedMonth,
    required this.selectedDate,
    required this.quests,
    required this.completedRecords,
    required this.onPreviousMonth,
    required this.onNextMonth,
    required this.onDaySelected,
  });

  final DateTime focusedMonth;
  final DateTime selectedDate;
  final List<QuestItem> quests;
  final List<CompletedQuestRecord> completedRecords;
  final VoidCallback onPreviousMonth;
  final VoidCallback onNextMonth;
  final ValueChanged<DateTime> onDaySelected;

  @override
  Widget build(BuildContext context) {
    final days = _visibleCalendarDays(focusedMonth);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x17000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              _SmallCalendarArrow(
                icon: Icons.keyboard_arrow_left_rounded,
                onTap: onPreviousMonth,
              ),
              Expanded(
                child: Text(
                  _monthLabel(focusedMonth),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF1C2940),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _SmallCalendarArrow(
                icon: Icons.keyboard_arrow_right_rounded,
                onTap: onNextMonth,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              for (final label in const ['S', 'M', 'T', 'W', 'T', 'F', 'S'])
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Color(0xFF9AA2B1),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              crossAxisSpacing: 7,
              mainAxisSpacing: 8,
              childAspectRatio: 0.72,
            ),
            itemCount: days.length,
            itemBuilder: (context, index) {
              final day = days[index];
              return _CalendarDayCell(
                day: day,
                isInMonth: day.month == focusedMonth.month,
                isToday: _isSameDay(day, DateTime.now()),
                isSelected: _isSameDay(day, selectedDate),
                quests: _questsForDate(quests, day),
                completedCount: _completedForDate(completedRecords, day).length,
                onTap: () => onDaySelected(day),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SmallCalendarArrow extends StatelessWidget {
  const _SmallCalendarArrow({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 34,
        height: 34,
        child: Icon(icon, color: const Color(0xFF1C2940), size: 24),
      ),
    );
  }
}

class _CalendarDayCell extends StatelessWidget {
  const _CalendarDayCell({
    required this.day,
    required this.isInMonth,
    required this.isToday,
    required this.isSelected,
    required this.quests,
    required this.completedCount,
    required this.onTap,
  });

  final DateTime day;
  final bool isInMonth;
  final bool isToday;
  final bool isSelected;
  final List<QuestItem> quests;
  final int completedCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dotColors = <Color>[
      for (final quest in quests.take(3))
        questCategoryStyleFor(quest.category).accentColor,
      if (completedCount > 0) const Color(0xFF6F63FF),
    ];

    final borderColor = isSelected
        ? const Color(0xFF1C2940)
        : isToday
        ? const Color(0xFFFF8B93)
        : Colors.transparent;

    final chipColor = isSelected
        ? const Color(0xFF1C2940)
        : isToday
        ? const Color(0xFFFF8B93)
        : Colors.transparent;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isInMonth
              ? (isSelected ? const Color(0xFFFFF1F2) : const Color(0xFFF8FAFD))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: borderColor, width: 1.4),
        ),
        child: Opacity(
          opacity: isInMonth ? 1 : 0.34,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: chipColor,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${day.day}',
                  style: TextStyle(
                    color: isSelected || isToday
                        ? Colors.white
                        : const Color(0xFF1C2940),
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: 5,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final color in dotColors.take(3)) ...[
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 2),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CalendarMetricCard extends StatelessWidget {
  const _CalendarMetricCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Color(0xFF1C2940),
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF9AA2B1),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CalendarAgendaSection extends StatelessWidget {
  const _CalendarAgendaSection({
    required this.title,
    required this.emptyText,
    required this.quests,
  });

  final String title;
  final String emptyText;
  final List<QuestItem> quests;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            title,
            style: const TextStyle(
              color: Color(0xFF1C2940),
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (quests.isEmpty)
          _CalendarEmptyTile(text: emptyText)
        else
          for (final quest in quests.take(6)) ...[
            _CalendarQuestTile(quest: quest),
            const SizedBox(height: 9),
          ],
      ],
    );
  }
}

class _CalendarQuestTile extends StatelessWidget {
  const _CalendarQuestTile({required this.quest});

  final QuestItem quest;

  @override
  Widget build(BuildContext context) {
    final style = questCategoryStyleFor(quest.category);
    final dueDate = quest.dueDate;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: style.accentColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(style.icon, color: style.accentColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  quest.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF1C2940),
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  dueDate == null ? '마감일 없음' : formatQuestDueDate(dueDate),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF8A8E98),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${quest.exp} EXP',
            style: const TextStyle(
              color: Color(0xFF8A8E98),
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarEmptyTile extends StatelessWidget {
  const _CalendarEmptyTile({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Color(0xFF9AA2B1),
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

DateTime _monthOnly(DateTime value) => DateTime(value.year, value.month);

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _isSameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

List<DateTime> _visibleCalendarDays(DateTime focusedMonth) {
  final firstDay = DateTime(focusedMonth.year, focusedMonth.month);
  final leadingDays = firstDay.weekday % 7;
  final startDay = firstDay.subtract(Duration(days: leadingDays));
  return [
    for (var index = 0; index < 42; index += 1)
      startDay.add(Duration(days: index)),
  ];
}

List<QuestItem> _questsForDate(List<QuestItem> quests, DateTime day) {
  final target = _dateOnly(day);
  return quests.where((quest) {
    final dueDate = normalizeQuestDueDate(quest.dueDate);
    return dueDate != null && _isSameDay(dueDate, target);
  }).toList()..sort((left, right) => left.title.compareTo(right.title));
}

List<CompletedQuestRecord> _completedForDate(
  List<CompletedQuestRecord> records,
  DateTime day,
) {
  final target = _dateOnly(day);
  return records.where((record) {
    final completedAt = DateTime.tryParse(record.completedAt)?.toLocal();
    return completedAt != null && _isSameDay(completedAt, target);
  }).toList();
}

List<QuestItem> _questsInMonth(List<QuestItem> quests, DateTime month) {
  return quests.where((quest) {
    final dueDate = normalizeQuestDueDate(quest.dueDate);
    return dueDate != null &&
        dueDate.year == month.year &&
        dueDate.month == month.month;
  }).toList();
}

List<CompletedQuestRecord> _completedInMonth(
  List<CompletedQuestRecord> records,
  DateTime month,
) {
  return records.where((record) {
    final completedAt = DateTime.tryParse(record.completedAt)?.toLocal();
    return completedAt != null &&
        completedAt.year == month.year &&
        completedAt.month == month.month;
  }).toList();
}

List<QuestItem> _upcomingQuests(List<QuestItem> quests, DateTime today) {
  final target = _dateOnly(today);
  final scheduled = quests.where((quest) {
    final dueDate = normalizeQuestDueDate(quest.dueDate);
    return dueDate != null && !dueDate.isBefore(target);
  }).toList()..sort((left, right) => left.dueDate!.compareTo(right.dueDate!));
  return scheduled;
}

String _shortMonthLabel(DateTime month) {
  const names = [
    'JAN',
    'FEB',
    'MAR',
    'APR',
    'MAY',
    'JUN',
    'JUL',
    'AUG',
    'SEP',
    'OCT',
    'NOV',
    'DEC',
  ];
  return names[month.month - 1];
}

String _monthLabel(DateTime month) {
  const names = [
    'JANUARY',
    'FEBRUARY',
    'MARCH',
    'APRIL',
    'MAY',
    'JUNE',
    'JULY',
    'AUGUST',
    'SEPTEMBER',
    'OCTOBER',
    'NOVEMBER',
    'DECEMBER',
  ];
  return '${names[month.month - 1]} ${month.year}';
}
