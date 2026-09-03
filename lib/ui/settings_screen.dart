import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/format.dart';
import '../notifications/notifier.dart';
import '../state/app_state.dart';
import 'how_it_works.dart';

/// Availability is the other half of the planner's input. Everything here
/// feeds straight back into a replan.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final weekly = state.availability;
    final weekTotal = List.generate(7, (i) => weekly.minutesByWeekday[i + 1] ?? 0)
        .fold(0, (a, b) => a + b);

    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text('Study time', style: theme.textTheme.titleMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Text(
            '${formatMinutes(weekTotal)} a week. Be honest here — an '
            'optimistic number just produces a plan you will fall behind on.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
        for (var day = 1; day <= 7; day++)
          _DaySlider(
            label: _weekdayNames[day - 1],
            minutes: weekly.minutesByWeekday[day] ?? 0,
            onChanged: (m) => state.setWeekdayMinutes(day, m),
          ),
        const Divider(height: 32),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text('Reminders', style: theme.textTheme.titleMedium),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: const Text('Re-request notification permissions'),
          subtitle: const Text(
              'Includes "Alarms & reminders", which Android hides in a '
              'separate screen'),
          onTap: () async {
            await state.notifier.requestPermissions();
            await state.refreshAlarms();
          },
        ),
        ListTile(
          leading: const Icon(Icons.notifications_none),
          title: const Text('Send a test reminder'),
          subtitle: const Text(
              'Fires in 1 minute. The only way to check delivery actually '
              'works without waiting for a real block'),
          onTap: () async {
            final when = await state.notifier.scheduleTest();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Test reminder set for '
                    '${formatClock(when.hour * 60 + when.minute)}. '
                    'Lock the phone and wait.',
                  ),
                  duration: const Duration(seconds: 6),
                ),
              );
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.sync),
          title: const Text('Reschedule all reminders'),
          subtitle: Text(
            'One reminder per study block for the next ${Notifier.windowDays} '
            'days. ${state.exactAlarmsAllowed ? "Exact timing is allowed." : "Exact alarms are blocked — reminders may arrive late."}',
          ),
          onTap: () async {
            await state.refreshAlarms();
            final pending = await state.notifier.pendingCount();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '$pending reminders set — one for each study block in the '
                    'next ${Notifier.windowDays} days.',
                  ),
                  duration: const Duration(seconds: 5),
                ),
              );
            }
          },
        ),
        const Divider(height: 32),
        ListTile(
          leading: const Icon(Icons.help_outline),
          title: const Text('How Prahar works'),
          subtitle: const Text(
              'What the tabs are for, and why blocks land where they do'),
          onTap: () => HowItWorks.open(context),
        ),
        const Divider(height: 32),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Text(
            'Everything stays on this device. No account, no server, no '
            'subscription.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
      ],
    );
  }
}

class _DaySlider extends StatelessWidget {
  const _DaySlider({
    required this.label,
    required this.minutes,
    required this.onChanged,
  });

  final String label;
  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: Slider(
              value: minutes.toDouble(),
              max: 720,
              divisions: 24, // half-hour steps
              label: formatMinutes(minutes),
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              formatMinutes(minutes),
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
