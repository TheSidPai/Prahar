import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/format.dart';
import '../domain/schedule.dart';
import '../state/app_state.dart';
import 'widgets.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final sessions = state.todaySessions;

    if (state.subjects.isEmpty) {
      return const EmptyState(
        icon: Icons.menu_book_outlined,
        title: 'Nothing to plan yet',
        message:
            'Add a subject and the topics you need to cover. Prahar works out '
            'the day-by-day schedule from there.',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        _Header(state: state),
        if (!state.exactAlarmsAllowed) const _ExactAlarmWarning(),
        if (state.feasibility != null)
          FeasibilityBanner(feasibility: state.feasibility!),
        const SizedBox(height: 8),
        for (final entry in state.todayLog)
          LoggedTile(
            entry: entry,
            color: Color(
                state.subjectFor(entry.subjectId)?.colorValue ?? 0xFF4F46E5),
          ),
        if (sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                state.todayLog.isEmpty
                    ? 'No study time scheduled today.'
                    : "That's everything for today.",
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          )
        else
          for (final s in sessions)
            SessionTile(
              session: s,
              color: Color(
                  state.subjectFor(s.subjectId)?.colorValue ?? 0xFF4F46E5),
              onDone: () => _confirmDone(context, state, s),
              onSkip: () => state.markSkipped(s),
            ),
      ],
    );
  }

  /// Asks for the *actual* time spent rather than assuming the plan was
  /// followed. That single number is what keeps future estimates honest.
  Future<void> _confirmDone(
      BuildContext context, AppState state, StudySession session) async {
    var minutes = session.durationMinutes;

    final result = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('How long did it take?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(session.topicTitle),
              const SizedBox(height: 16),
              Text(formatMinutes(minutes),
                  style: Theme.of(context).textTheme.headlineSmall),
              Slider(
                value: minutes.toDouble(),
                min: 5,
                max: 180,
                divisions: 35,
                onChanged: (v) => setState(() => minutes = v.round()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, minutes),
              child: const Text('Log it'),
            ),
          ],
        ),
      ),
    );

    if (result != null) {
      await state.markDone(session, actualMinutes: result);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = state.doneMinutesToday;
    final planned = state.plannedMinutesToday;
    final progress = planned == 0 ? 0.0 : (done / planned).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDateFull(state.today),
                  style: theme.textTheme.titleLarge),
              if (state.streak > 0)
                Row(children: [
                  const Icon(Icons.local_fire_department, size: 18),
                  const SizedBox(width: 4),
                  Text('${state.streak}', style: theme.textTheme.titleMedium),
                ]),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: progress, minHeight: 8),
          ),
          const SizedBox(height: 6),
          Text(
            planned == 0
                ? 'Nothing planned today'
                : '${formatMinutes(done)} of ${formatMinutes(planned)}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Android 12+ silently downgrades alarms to inexact ones unless the user
/// grants this. A 6pm reminder arriving at 7:20pm is how a study app loses a
/// student's trust, so it gets called out rather than failing quietly.
class _ExactAlarmWarning extends StatelessWidget {
  const _ExactAlarmWarning();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        const Icon(Icons.alarm_off, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Exact alarms are off, so reminders may arrive late. Enable '
            '"Alarms & reminders" for Prahar in Android settings.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ]),
    );
  }
}
