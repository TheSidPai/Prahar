import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/format.dart';
import '../domain/models.dart';
import '../state/app_state.dart';
import 'subject_detail_screen.dart';
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

    final total = state.subjects.fold(
        0, (a, s) => a + state.topicsFor(s.id).fold(0, (b, t) => b + t.estimatedMinutes));
    final done = state.subjects.fold(
        0, (a, s) => a + state.topicsFor(s.id).fold(0, (b, t) => b + t.completedMinutes));

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 90),
      children: [
        _OverallCard(done: done, total: total, streak: state.streak),
        for (final subject in state.subjects)
          _SubjectProgress(
            subject: subject,
            topics: state.topicsFor(subject.id),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Text(
            'Tap a subject to see its topics.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ),
      ],
    );
  }
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({
    required this.done,
    required this.total,
    required this.streak,
  });

  final int done;
  final int total;
  final int streak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${(pct * 100).round()}%',
                    style: theme.textTheme.displaySmall),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('of everything covered',
                      style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
                const Spacer(),
                if (streak > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      const Icon(Icons.local_fire_department, size: 18),
                      const SizedBox(width: 4),
                      Text('$streak d', style: theme.textTheme.titleMedium),
                    ]),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(value: pct, minHeight: 10),
            ),
            const SizedBox(height: 8),
            Text(
              '${formatMinutes(done)} done · ${formatMinutes(total - done)} left',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
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

    // The question a student actually has: at this rate, do I finish in time?
    final remaining = total - done;
    final perDay = (daysLeft != null && daysLeft > 0)
        ? (remaining / daysLeft).ceil()
        : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => SubjectDetailScreen(subjectId: subject.id),
          ),
        ),
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
                    daysLeft < 0
                        ? 'exam passed'
                        : daysLeft == 0
                            ? 'exam today'
                            : '$daysLeft days left',
                    style: theme.textTheme.bodySmall,
                  ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 18),
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
              const SizedBox(height: 8),
              Text(
                '${formatMinutes(done)} of ${formatMinutes(total)} · '
                '${topics.where((t) => t.isDone).length} of ${topics.length} topics done',
                style: theme.textTheme.bodySmall,
              ),
              if (perDay != null && remaining > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Needs ${formatMinutes(perDay)} a day to finish in time',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
              if (remaining == 0 && total > 0) ...[
                const SizedBox(height: 4),
                Text('Covered — reviews continue',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.primary)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
