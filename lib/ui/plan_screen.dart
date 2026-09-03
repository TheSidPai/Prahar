import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/format.dart';
import '../domain/models.dart';
import '../state/app_state.dart';
import 'widgets.dart';

/// The next fortnight, day by day. Enough to see the shape of the plan without
/// pretending the far future is meaningful — it will be replanned many times
/// before it arrives.
class PlanScreen extends StatelessWidget {
  const PlanScreen({super.key, this.days = 14});

  final int days;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final plan = state.plan;

    if (plan == null || plan.sessions.isEmpty) {
      return const EmptyState(
        icon: Icons.calendar_month_outlined,
        title: 'No schedule yet',
        message: 'Add subjects and topics, and a plan appears here.',
      );
    }

    final today = state.today;

    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 90),
      itemCount: days,
      itemBuilder: (context, i) {
        final day = today.add(Duration(days: i));
        final sessions = plan.onDate(day);
        final capacity = state.availability.minutesOn(day);

        return _DaySection(
          day: day,
          isToday: i == 0,
          capacity: capacity,
          children: [
            if (sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(30, 2, 16, 10),
                child: Text(
                  capacity == 0 ? 'Day off' : 'Nothing scheduled',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline),
                ),
              )
            else
              for (final s in sessions)
                SessionTile(
                  session: s,
                  color: Color(
                      state.subjectFor(s.subjectId)?.colorValue ?? 0xFF4F46E5),
                ),
          ],
        );
      },
    );
  }
}

class _DaySection extends StatelessWidget {
  const _DaySection({
    required this.day,
    required this.isToday,
    required this.capacity,
    required this.children,
  });

  final DateTime day;
  final bool isToday;
  final int capacity;
  final List<Widget> children;

  static const _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(children: [
            Text(
              isToday
                  ? 'Today'
                  : '${_weekdays[day.weekday - 1]} ${formatDate(day)}',
              style: theme.textTheme.titleSmall?.copyWith(
                color: isToday ? theme.colorScheme.primary : null,
              ),
            ),
            const Spacer(),
            Text(formatMinutes(capacity), style: theme.textTheme.bodySmall),
          ]),
        ),
        ...children,
      ],
    );
  }
}

/// Per-subject progress, which is the question students actually ask:
/// "am I on track for Physics?"
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.subjects.isEmpty) {
      return const EmptyState(
        icon: Icons.insights_outlined,
        title: 'No progress yet',
        message: 'Add a subject to start tracking.',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 90),
      children: [
        for (final subject in state.subjects)
          _SubjectProgress(subject: subject, topics: state.topicsFor(subject.id)),
      ],
    );
  }
}

class _SubjectProgress extends StatelessWidget {
  const _SubjectProgress({required this.subject, required this.topics});

  final Subject subject;
  final List<Topic> topics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = topics.fold(0, (a, t) => a + t.estimatedMinutes);
    final done = topics.fold(0, (a, t) => a + t.completedMinutes);
    final progress = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final daysLeft = subject.examDate?.difference(DateTime.now()).inDays;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Color(subject.colorValue),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(subject.name, style: theme.textTheme.titleMedium),
              const Spacer(),
              if (daysLeft != null)
                Text(
                  daysLeft < 0 ? 'past' : '$daysLeft days',
                  style: theme.textTheme.bodySmall,
                ),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                color: Color(subject.colorValue),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${formatMinutes(done)} of ${formatMinutes(total)} · '
              '${topics.where((t) => t.isDone).length}/${topics.length} topics',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
