import 'package:flutter/material.dart';

import '../../model/mood.dart';
import '../../viewmodel/diary_view_model.dart';

class CompactCalendar extends StatefulWidget {
  final List<dynamic> entries;
  final int currentStreak;
  final DiaryViewModel vm;

  const CompactCalendar({super.key, required this.entries, required this.currentStreak, required this.vm});

  @override
  State<CompactCalendar> createState() => _CompactCalendarState();
}

class _CompactCalendarState extends State<CompactCalendar> {
  late DateTime _currentMonth;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byDay = _groupByDay(widget.entries);
    final days = _buildMonthDays(_currentMonth);
    final monthName = _monthYearLabel(_currentMonth);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(icon: const Icon(Icons.chevron_left, size: 20), onPressed: () => setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1))),
              Text(monthName, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500)),
              IconButton(icon: const Icon(Icons.chevron_right, size: 20), onPressed: () => setState(() => _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1))),
            ],
          ),
          const SizedBox(height: 4),
          _WeekdayHeader(),
          const SizedBox(height: 4),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 1),
            itemCount: days.length,
            itemBuilder: (context, index) {
              final d = days[index];
              if (d == null) return const SizedBox.shrink();
              final dayKey = _dateOnly(d);
              final isToday = _isSameDate(dayKey, _dateOnly(DateTime.now()));
              final hasEntries = byDay.containsKey(dayKey);
              final isCurrentMonth = d.month == _currentMonth.month;
              final rating = widget.vm.getDailyAverageRating(dayKey);
              final moods = widget.vm.getMoodsForDay(dayKey);

              return _CompactDayCell(date: d, isCurrentMonth: isCurrentMonth, isToday: isToday, hasEntries: hasEntries, rating: rating, moods: moods);
            },
          ),
        ],
      ),
    );
  }

  Map<DateTime, List<dynamic>> _groupByDay(List<dynamic> entries) {
    final map = <DateTime, List<dynamic>>{};
    for (final e in entries) {
      final key = _dateOnly(e.date as DateTime);
      map.putIfAbsent(key, () => []);
      map[key]!.add(e);
    }
    return map;
  }

  List<DateTime?> _buildMonthDays(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final startWeekday = first.weekday % 7;
    final list = <DateTime?>[];
    for (int i = 0; i < startWeekday; i++) {
      list.add(null);
    }
    for (int d = 1; d <= daysInMonth; d++) {
      list.add(DateTime(month.year, month.month, d));
    }
    while (list.length % 7 != 0) {
      list.add(null);
    }
    return list;
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  bool _isSameDate(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
  String _monthYearLabel(DateTime d) => '${_monthNameEn(d.month)} ${d.year}';
  String _monthNameEn(int m) {
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[m - 1];
  }
}

class _WeekdayHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return Row(
      children: List.generate(
        7,
        (i) => Expanded(
          child: Center(child: Text(days[i], style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10))),
        ),
      ),
    );
  }
}

class _CompactDayCell extends StatelessWidget {
  final DateTime date;
  final bool isCurrentMonth;
  final bool isToday;
  final bool hasEntries;
  final int? rating;
  final List<Mood> moods;

  const _CompactDayCell({required this.date, required this.isCurrentMonth, required this.isToday, required this.hasEntries, this.rating, this.moods = const []});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Color? bg;
    if (hasEntries) {
      if ((rating ?? 0) > 0) {
        switch (rating) {
          case 5:
            bg = Colors.green.withValues(alpha: 0.3);
            break;
          case 4:
            bg = Colors.lightGreen.withValues(alpha: 0.3);
            break;
          case 3:
            bg = Colors.orange.withValues(alpha: 0.3);
            break;
          case 2:
            bg = Colors.deepOrange.withValues(alpha: 0.3);
            break;
          case 1:
            bg = Colors.red.withValues(alpha: 0.3);
            break;
        }
      } else {
        bg = theme.colorScheme.primary.withValues(alpha: 0.2);
      }
    }

    final fg = isCurrentMonth ? theme.textTheme.bodySmall?.color : theme.textTheme.bodySmall?.color?.withValues(alpha: 0.3);

    final moodEmojis = moods.map((mood) => mood.emoji).toList();
    final displayEmojis = moodEmojis.take(9).toList();
    const maxEmojisPerRow = 3;
    final emojiRows = <MapEntry<String, double>>[];
    for (var i = 0; i < displayEmojis.length; i += maxEmojisPerRow) {
      final end = (i + maxEmojisPerRow > displayEmojis.length) ? displayEmojis.length : i + maxEmojisPerRow;
      final rowEmojis = displayEmojis.sublist(i, end);
      final fontSize = (10 - (rowEmojis.length - 1)).clamp(8, 10).toDouble(); // Keep text legible while fitting the cell.
      emojiRows.add(MapEntry(rowEmojis.join(' '), fontSize));
    }
    // final extraCount = moodEmojis.length - displayEmojis.length;

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: isToday ? Border.all(color: theme.colorScheme.primary, width: 2) : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '${date.day}',
            style: TextStyle(fontSize: 12, fontWeight: isToday ? FontWeight.bold : FontWeight.normal, color: fg),
          ),
          if (emojiRows.isNotEmpty) ...[
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final row in emojiRows)
                  Text(
                    row.key,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: row.value, color: fg),
                  ),
              ],
            ),
            // if (extraCount > 0) Text('+$extraCount', style: TextStyle(fontSize: 8, color: fg?.withValues(alpha: 0.8))),
          ],
        ],
      ),
    );
  }
}
