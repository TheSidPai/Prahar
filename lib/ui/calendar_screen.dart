import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/format.dart';
import '../domain/models.dart';
import '../state/app_state.dart';
import 'busy_slots_screen.dart';

/// A month view for exams and one-off busy days. Deliberately not a full
/// timetable — showing every hour of every day at this size is unreadable, and
/// the daily grid already exists on the Plan tab. This answers a different
/// question: "when are the exams, and are any of them close together?"
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final today = dateOnly(DateTime.now());

    // Two independent groupings: exam dates (permanent, subject-coloured) and
    // one-off busy dates (transient, neutral marker).
    final examsByKey = <String, List<Subject>>{};
    for (final s in state.subjects) {
      final e = s.examDate;
      if (e == null) continue;
      examsByKey.putIfAbsent(dateKey(e), () => []).add(s);
    }
    final busyDates = <String>{
      for (final b in state.availability.busy)
        if (!b.repeatsWeekly && b.date != null) dateKey(b.date!),
    };

    // A month grid starts on the previous Monday and runs for exactly six
    // weeks. Six is always enough for any month; using the actual length
    // instead makes the grid change height row by row.
    final firstOfMonth = _month;
    final leadingBlanks = (firstOfMonth.weekday - DateTime.monday + 7) % 7;
    final gridStart = firstOfMonth.subtract(Duration(days: leadingBlanks));

    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        _MonthHeader(
          month: _month,
          onPrev: () =>
              setState(() => _month = DateTime(_month.year, _month.month - 1)),
          onNext: () =>
              setState(() => _month = DateTime(_month.year, _month.month + 1)),
          onToday: () =>
              setState(() => _month = DateTime(today.year, today.month)),
        ),
        const SizedBox(height: 8),
        _WeekdayHeader(),
        const SizedBox(height: 6),
        for (var week = 0; week < 6; week++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: Row(
              children: [
                for (var d = 0; d < 7; d++) ...[
                  Expanded(
                    child: _DayCell(
                      day: gridStart.add(Duration(days: week * 7 + d)),
                      currentMonth: _month.month,
                      today: today,
                      exams:
                          examsByKey[dateKey(
                            gridStart.add(Duration(days: week * 7 + d)),
                          )] ??
                          const [],
                      isBusy: busyDates.contains(
                        dateKey(gridStart.add(Duration(days: week * 7 + d))),
                      ),
                    ),
                  ),
                  if (d < 6) const SizedBox(width: 4),
                ],
              ],
            ),
          ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            children: [
              Text('Upcoming exams', style: theme.textTheme.titleSmall),
              const Spacer(),
              TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const BusySlotsScreen(),
                  ),
                ),
                icon: const Icon(Icons.event_busy_outlined, size: 18),
                label: const Text('Busy slots'),
              ),
            ],
          ),
        ),
        _ExamList(subjects: state.subjects, today: today),
      ],
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  static const _names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: onPrev),
          Expanded(
            child: Center(
              child: TextButton(
                onPressed: onToday,
                child: Text(
                  '${_names[month.month - 1]} ${month.year}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: onNext),
        ],
      ),
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          for (final d in days)
            Expanded(
              child: Center(
                child: Text(
                  d,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.currentMonth,
    required this.today,
    required this.exams,
    required this.isBusy,
  });

  final DateTime day;
  final int currentMonth;
  final DateTime today;
  final List<Subject> exams;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final outside = day.month != currentMonth;
    final isToday = dateKey(day) == dateKey(today);

    final dayText = TextStyle(
      color: outside
          ? theme.colorScheme.outline.withValues(alpha: 0.6)
          : (isToday
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface),
      fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
    );

    // The highlight is now a circle that hugs the digit rather than filling
    // the whole cell — otherwise the digit sits in the top-left corner of a
    // rectangle and looks off-centre inside it. Exam dots live in a strip
    // *beneath* the digit so the digit's alignment is never affected by them.
    // A fixed height rather than an aspect ratio. The ratio made the cell's
    // height a function of the column's width, so in a narrow column — the
    // Plan tab's second pane in landscape, at about 44dp per cell — the box
    // shrank below the 52dp its own contents need and the digit overflowed
    // its cell. 56 is what 0.9 gave at a phone's portrait width, so nothing
    // moves in the common case; it simply stops shrinking past what fits.
    return SizedBox(
      height: 56,
      child: Container(
        decoration: BoxDecoration(
          color: isBusy && !isToday
              ? theme.colorScheme.surfaceContainerHighest
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isBusy && !isToday
              ? Border.all(color: theme.colorScheme.outlineVariant)
              : null,
        ),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isToday ? theme.colorScheme.primary : Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: Text('${day.day}', style: dayText),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 6,
              child: exams.isEmpty
                  ? const SizedBox.shrink()
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final s in exams.take(3)) ...[
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: Color(s.colorValue),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 3),
                        ],
                        if (exams.length > 3)
                          Text(
                            '+${exams.length - 3}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.outline,
                              fontSize: 9,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExamList extends StatelessWidget {
  const _ExamList({required this.subjects, required this.today});

  final List<Subject> subjects;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final upcoming =
        subjects
            .where((s) => s.examDate != null && !s.examDate!.isBefore(today))
            .toList()
          ..sort((a, b) => a.examDate!.compareTo(b.examDate!));

    if (upcoming.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
        child: Text(
          'No upcoming exams. Add exam dates on Subjects to see them here.',
          style: theme.textTheme.bodySmall,
        ),
      );
    }

    return Column(
      children: [
        for (var i = 0; i < upcoming.length; i++) ...[
          _ExamRow(
            subject: upcoming[i],
            today: today,
            // "3 days after Physics" — closeness between exams is exactly what
            // this screen exists to reveal.
            gapAfterPrevious: i == 0
                ? null
                : upcoming[i].examDate!
                      .difference(upcoming[i - 1].examDate!)
                      .inDays,
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _ExamRow extends StatelessWidget {
  const _ExamRow({
    required this.subject,
    required this.today,
    required this.gapAfterPrevious,
  });

  final Subject subject;
  final DateTime today;
  final int? gapAfterPrevious;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exam = subject.examDate!;
    final daysLeft = dateOnly(exam).difference(today).inDays;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 44,
                decoration: BoxDecoration(
                  color: Color(subject.colorValue),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(subject.name, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 3),
                    Text(
                      subject.examMinuteOfDay == null
                          ? formatDateFull(exam)
                          : '${formatDateFull(exam)}, '
                                '${formatClock(subject.examMinuteOfDay!)}',
                      style: theme.textTheme.bodySmall,
                    ),
                    if (gapAfterPrevious != null && gapAfterPrevious! <= 3) ...[
                      const SizedBox(height: 6),
                      Text(
                        '$gapAfterPrevious day${gapAfterPrevious == 1 ? '' : 's'} after the previous — tight',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.tertiary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    daysLeft == 0 ? 'Today' : '$daysLeft d',
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    'left',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
