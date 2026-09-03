import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/format.dart';
import '../domain/schedule.dart';
import '../state/app_state.dart';
import '../domain/preferences.dart';
import 'glass.dart';
import 'how_it_works.dart';
import 'subjects_screen.dart';
import 'widgets.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final sessions = state.todaySessions;

    // First run: explain the app rather than showing an empty page. Someone
    // who has just installed this has no idea what the five tabs are for.
    if (state.subjects.isEmpty) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
            child: Text('Welcome to Prahar',
                style: theme.textTheme.headlineSmall),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(
              'A study planner that tells you the truth about whether your '
              'plan is possible.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const HowItWorks(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            child: FilledButton.icon(
              onPressed: () => showSubjectSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('Add your first subject'),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        _Header(state: state),
        if (!state.batteryExempt) _BatteryWarning(state: state),
        if (!state.exactAlarmsAllowed) const _ExactAlarmWarning(),
        if (state.feasibility != null)
          FeasibilityBanner(feasibility: state.feasibility!),
        const SizedBox(height: 8),
        for (final entry in state.todayLog)
          LoggedTile(
            entry: entry,
            color: Color(
                state.subjectFor(entry.subjectId)?.colorValue ?? 0xFF4F46E5),
            onUndo: () async {
              await state.undoLogged(entry);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Undone — ${entry.topicTitle} is back'),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
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
              onSkip: () => _confirmSkip(context, state, s),
            ),
      ],
    );
  }

  /// Skipping is irreversible *and* costs the slot: the block's time is
  /// subtracted from today so the work rolls to tomorrow rather than being
  /// offered again this afternoon. Two consequences behind one tap, so it asks
  /// first and says what will happen.
  Future<void> _confirmSkip(
      BuildContext context, AppState state, StudySession session) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Skip this block?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.topicTitle,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 12),
            Text(
              'The work moves to a later day, and today loses '
              '${formatMinutes(session.durationMinutes)} of study time so it '
              "isn't offered again this afternoon.",
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 10),
            Text(
              'This cannot be undone.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Skip'),
          ),
        ],
      ),
    );
    if (ok == true) await state.markSkipped(session);
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
    final glass = state.prefs.materialChoice == MaterialChoice.glass;

    // The header is the "hero surface" per the glass rule of one glass panel
    // per screen — wrapped when the material is glass, plain padding when
    // matte. Keeping both branches close together stops them drifting.
    final content = Column(
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
      );

    if (!glass) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: content,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.all(18),
        child: content,
      ),
    );
  }
}

/// The single most important warning in the app.
///
/// Without a battery-optimisation exemption Android freezes the process, and a
/// perfectly registered exact alarm wakes nothing. The reminder then appears
/// only when the app is next opened by hand — which is exactly when it is
/// worthless. Confirmed on a Xiaomi device: identical code, exemption off,
/// nothing arrived; exemption on, it arrived to the minute.
class _BatteryWarning extends StatelessWidget {
  const _BatteryWarning({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.battery_alert, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Reminders will not arrive',
                  style: theme.textTheme.titleSmall),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'Android is allowed to freeze Prahar in the background, so study '
            'reminders will only appear when you open the app yourself. Allow '
            'it to run unrestricted and they arrive on time.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () async {
                final ok = await state.requestBatteryExemption();
                if (context.mounted && !ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Still restricted. Settings > Apps > Prahar > Battery '
                        '> No restrictions, and turn on Autostart.',
                      ),
                      duration: Duration(seconds: 8),
                    ),
                  );
                }
              },
              child: const Text('Fix this'),
            ),
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
