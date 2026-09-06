import 'package:flutter/material.dart';

import '../planner/planner.dart';
import 'brand.dart';

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
    MaterialPageRoute<void>(builder: (_) => const HowItWorks(showAppBar: true)),
  );

  @override
  Widget build(BuildContext context) {
    final body = ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
      children: [
        // Small brand header inside the guide — only when it opens as its
        // own page (not when it appears inline on the first-run Today
        // screen, which already carries the full logo above it).
        if (showAppBar)
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 18),
            child: PraharLogo(markSize: 40, filled: false),
          ),

        const _Opening(),
        const SizedBox(height: 26),
        const _Journey(),
        const SizedBox(height: 8),
        const _TabGuide(),
        const SizedBox(height: 8),
        const _ScheduleRules(),
        const SizedBox(height: 8),
        const _Honesty(),
      ],
    );

    if (!showAppBar) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('How Prahar works')),
      body: body,
    );
  }
}

/// What the app is for, before what to press.
class _Opening extends StatelessWidget {
  const _Opening();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Four steps, once.',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tell Prahar what you have to learn and when you are free. It works '
          'out the rest, every day, and tells you plainly when the plan will '
          'not fit.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}

/// The four steps as a path rather than four paragraphs.
///
/// They were a numbered list: correct, and completely inert — the reader had
/// no sense of being anywhere in a sequence, and nothing on the page showed
/// what any step produced. Two changes fix that without adding a word.
///
/// A **connector** runs from each node to the next, so the eye is carried down
/// a route with an end. The line stops at the last node, which is the only way
/// a path says "this is all of it".
///
/// Each step then **shows its own outcome** in the app's own visual language —
/// the exam pill, the estimate bars, the day track with its busy bands, a
/// finished block. They are drawn from the same primitives the real screens
/// use, so the guide is teaching the vocabulary the app will speak, not
/// illustrating it with something invented for the page.
class _Journey extends StatelessWidget {
  const _Journey();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _JourneyStep(
          n: '1',
          title: 'Add a subject',
          body:
              'Give it an exam date. That date is what makes the schedule '
              'urgent — without one, Prahar treats the subject as background '
              'work and everything else takes priority.',
          visual: _ExamPill(),
        ),
        _JourneyStep(
          n: '2',
          title: 'Break it into topics',
          body:
              'Chapters work well. For each one you enter pages, problems or '
              'minutes — pages are easiest, and Prahar converts them. It then '
              'learns your real reading speed and corrects the estimate.',
          visual: _EstimateBars(),
        ),
        _JourneyStep(
          n: '3',
          title: 'Say when you are free',
          body:
              'Set the hours blocks may be placed between, then mark class '
              'hours, lunch, a shift — anything the schedule should route '
              'around. What is left is what you can genuinely spend.',
          visual: _DayTrack(),
        ),
        _JourneyStep(
          n: '4',
          title: 'Follow Today, and tell it the truth',
          body:
              'Mark blocks done with the time they actually took. Missing a '
              'day is fine — the plan is rebuilt from scratch whenever '
              'anything changes, so work moves forward instead of piling up '
              'as overdue.',
          visual: _DoneBlock(),
          last: true,
        ),
      ],
    );
  }
}

class _JourneyStep extends StatelessWidget {
  const _JourneyStep({
    required this.n,
    required this.title,
    required this.body,
    required this.visual,
    this.last = false,
  });

  final String n;
  final String title;
  final String body;
  final Widget visual;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.tertiary;

    // IntrinsicHeight so the connector knows how tall the step beside it is.
    // Expensive in general; four short rows, once, on a page nobody scrolls
    // twice.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Column(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                    border: Border.all(color: accent.withValues(alpha: 0.55)),
                  ),
                  child: Text(
                    n,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(1),
                        // Fading downward, so the path leads rather than
                        // fences.
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            accent.withValues(alpha: 0.35),
                            accent.withValues(alpha: 0.10),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    body,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  visual,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- vignettes
//
// Small, drawn from the same primitives the real screens use. None of them is
// interactive and none reads live data: they are a picture of the idea, and
// wiring them to real state would make the guide lie on an empty install.

/// Step 1: a subject, and the date that gives it urgency.
class _ExamPill extends StatelessWidget {
  const _ExamPill();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: const BoxDecoration(
            color: Color(0xFF4F46E5),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        // Flexible: the subject name is the one string here that could be
        // wider than the row at a large font.
        Flexible(
          child: Text(
            'Thermodynamics',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: theme.colorScheme.tertiary.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '12 Oct',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.tertiary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

/// Step 2: topics, each with an estimate that fills as it is done.
class _EstimateBars extends StatelessWidget {
  const _EstimateBars();

  static const _rows = [
    ('Entropy', 0.75, '120 pages'),
    ('Heat engines', 0.35, '90 pages'),
    ('Cycles', 0.0, '60 pages'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // Label above, bar below, rather than three columns in a row. The
        // columns had fixed widths, which is fine at 411dp and overflows at
        // 320 or at a 1.5x font — a caption and a bar stacked cannot.
        for (final (name, fill, amount) in _rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      amount,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: fill,
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Step 3: a day, with the parts already spoken for. The same track the week
/// view draws, so the reader meets the grammar here first.
class _DayTrack extends StatelessWidget {
  const _DayTrack();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget band(int flex, Color colour) =>
        Expanded(flex: flex, child: ColoredBox(color: colour));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 24,
            child: Row(
              children: [
                band(3, theme.colorScheme.surfaceContainerHighest),
                band(4, theme.colorScheme.onSurface.withValues(alpha: 0.16)),
                band(2, theme.colorScheme.surfaceContainerHighest),
                band(3, const Color(0xFF4F46E5).withValues(alpha: 0.9)),
                band(1, theme.colorScheme.surfaceContainerHighest),
                band(3, const Color(0xFFD97706).withValues(alpha: 0.9)),
                band(2, theme.colorScheme.surfaceContainerHighest),
              ],
            ),
          ),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            _Key(
              colour: theme.colorScheme.onSurface.withValues(alpha: 0.16),
              label: 'Busy',
            ),
            const SizedBox(width: 14),
            _Key(colour: const Color(0xFF4F46E5), label: 'Study'),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.colour, required this.label});

  final Color colour;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }
}

/// Step 4: a block, finished, with the time it really took.
class _DoneBlock extends StatelessWidget {
  const _DoneBlock();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 3,
          height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFF4F46E5),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Entropy',
                style: theme.textTheme.bodyMedium?.copyWith(
                  decoration: TextDecoration.lineThrough,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'planned 40m · took 52m',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.check_circle_rounded,
          size: 20,
          color: theme.colorScheme.tertiary,
        ),
      ],
    );
  }
}

class _TabGuide extends StatelessWidget {
  const _TabGuide();

  static const _tabs = [
    (Icons.today_outlined, 'Today', 'What to study now, and nothing else.'),
    (
      Icons.calendar_month_outlined,
      'Plan',
      'Two views: Days shows the next fortnight; Month shows the exam calendar.',
    ),
    // Not `insights`: Progress is drawn with PraharProgressGlyph in the nav
    // bar now, and a guide showing a different icon than the tab it names is
    // worse than no icon.
    (
      Icons.donut_large_outlined,
      'Progress',
      'How far through each subject you are, and how many minutes a day it now needs.',
    ),
    (
      Icons.library_books_outlined,
      'Subjects',
      'Your syllabus: subjects, their topics, and what is left.',
    ),
    (
      Icons.settings_outlined,
      'Settings',
      'Study time, busy slots, appearance, and reminders.',
    ),
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
      (
        'Block length',
        'up to ${c.maxSessionMinutes} min, never under ${c.minSessionMinutes}',
      ),
      ('Break between blocks', '${c.breakMinutes} min'),
      (
        'Same subject in a row',
        'at most ${c.maxConsecutiveSameSubject}, so subjects interleave',
      ),
      (
        'Reviews after finishing',
        'day ${c.reviewOffsetDays.join(', ')} afterwards',
      ),
      (
        'Order',
        'whichever subject needs the most minutes per day to finish in time',
      ),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Why blocks land where they do',
              style: theme.textTheme.titleSmall,
            ),
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
          Row(
            children: [
              const Icon(Icons.balance, size: 18),
              const SizedBox(width: 8),
              Text(
                'It will tell you when it does not fit',
                style: theme.textTheme.titleSmall,
              ),
            ],
          ),
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
