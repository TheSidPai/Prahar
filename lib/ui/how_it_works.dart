import 'package:flutter/material.dart';

import '../planner/planner.dart';

/// Explains what the app does and why blocks land where they do.
///
/// Shown in place of an empty Today screen on first run, and reachable from
/// Settings afterwards. It exists because the app is not self-evident: five
/// tabs appear, a schedule materialises, and nothing says on what basis. A
/// planner the user does not trust is a planner they stop opening.
class HowItWorks extends StatelessWidget {
  const HowItWorks({super.key, this.showAppBar = false});

  final bool showAppBar;

  static Future<void> open(BuildContext context) => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => const HowItWorks(showAppBar: true),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final body = ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
      children: const [
        _Step(
          n: '1',
          title: 'Add a subject',
          body: 'Give it an exam date. That date is what makes the schedule '
              'urgent — without one, Prahar treats the subject as background '
              'work and everything else takes priority.',
        ),
        _Step(
          n: '2',
          title: 'Break it into topics',
          body: 'Chapters work well. For each one you enter pages, problems '
              'or minutes — pages are easiest, and Prahar converts them. It '
              'then learns your real reading speed and corrects the estimate.',
        ),
        _Step(
          n: '3',
          title: 'Say when you are free',
          body: 'In Settings → Study window, set the hours blocks may be '
              'placed between. In Busy slots, mark class hours, lunch, a shift '
              '— anything the schedule should route around. Then Study time '
              'says how many minutes you can genuinely spend each day.',
        ),
        _Step(
          n: '4',
          title: 'Follow Today, and tell it the truth',
          body: 'Mark blocks done with the time they actually took. Missing a '
              'day is fine — the plan is rebuilt from scratch every time '
              'anything changes, so work moves forward instead of piling up '
              'as overdue.',
        ),
        SizedBox(height: 8),
        _TabGuide(),
        SizedBox(height: 8),
        _ScheduleRules(),
        SizedBox(height: 8),
        _Honesty(),
      ],
    );

    if (!showAppBar) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('How Prahar works')),
      body: body,
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.title, required this.body});

  final String n;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(n, style: theme.textTheme.labelLarge),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabGuide extends StatelessWidget {
  const _TabGuide();

  static const _tabs = [
    (Icons.today_outlined, 'Today', 'What to study now, and nothing else.'),
    (Icons.calendar_month_outlined, 'Plan',
        'Two views: Days shows the next fortnight; Month shows the exam calendar.'),
    (Icons.insights_outlined, 'Progress',
        'How far through each subject you are, and how many minutes a day it now needs.'),
    (Icons.library_books_outlined, 'Subjects',
        'Your syllabus: subjects, their topics, and what is left.'),
    (Icons.settings_outlined, 'Settings',
        'Study time, busy slots, appearance, and reminders.'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('The five tabs', style: theme.textTheme.titleSmall),
            const SizedBox(height: 12),
            for (final (icon, name, what) in _tabs)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, size: 18, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: RichText(
                        text: TextSpan(
                          style: theme.textTheme.bodySmall,
                          children: [
                            TextSpan(
                              text: '$name — ',
                              style: theme.textTheme.labelLarge,
                            ),
                            TextSpan(
                              text: what,
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
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

/// The scheduling rules, stated plainly and read from the live config rather
/// than retyped, so this cannot drift out of date.
class _ScheduleRules extends StatelessWidget {
  const _ScheduleRules();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const c = PlannerConfig();

    String hhmm(int m) =>
        '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

    final rules = <(String, String)>[
      ('Study window', '${hhmm(c.dayStartMinute)} to ${hhmm(c.dayEndMinute)}'),
      ('Block length', 'up to ${c.maxSessionMinutes} min, never under ${c.minSessionMinutes}'),
      ('Break between blocks', '${c.breakMinutes} min'),
      ('Same subject in a row', 'at most ${c.maxConsecutiveSameSubject}, so subjects interleave'),
      ('Reviews after finishing', 'day ${c.reviewOffsetDays.join(', ')} afterwards'),
      ('Order', 'whichever subject needs the most minutes per day to finish in time'),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Why blocks land where they do',
                style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            for (final (k, v) in rules)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 132,
                      child: Text(k, style: theme.textTheme.bodySmall),
                    ),
                    Expanded(
                      child: Text(
                        v,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Subjects are ordered by pressure, not by which exam is nearest. '
              'Forty hours due in two months needs more of today than one hour '
              'due next week.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Honesty extends StatelessWidget {
  const _Honesty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.balance, size: 18),
            const SizedBox(width: 8),
            Text('It will tell you when it does not fit',
                style: theme.textTheme.titleSmall),
          ]),
          const SizedBox(height: 8),
          Text(
            'If the work needs more hours than you have before an exam, Prahar '
            'says so, and says by how much, per subject. It will not quietly '
            'produce a schedule that cannot be finished.',
            style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }
}
