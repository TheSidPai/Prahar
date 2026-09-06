import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/format.dart';
import '../domain/models.dart';
import '../domain/preferences.dart';
import '../planner/calibration.dart';
import '../state/app_state.dart';
import 'calendar_screen.dart';
import 'glass.dart';
import 'layout.dart';
import 'subject_detail_screen.dart';
import 'week_screen.dart';
import 'widgets.dart';

/// The Plan tab combines the near-term day list with a month calendar.
/// Both answer "when will this happen"; the difference is zoom.
/// Plan's body: the fortnight, the month, or both at once.
///
/// The Days/Month control that chooses between them is *not* here — it is in
/// the app bar, drawn into the same pane of glass as the title, because it is
/// the header of this screen rather than the first row of its content. So this
/// widget is told which view to show instead of owning that state.
class PlanTabs extends StatelessWidget {
  const PlanTabs({super.key, required this.view});

  final int view;

  @override
  Widget build(BuildContext context) {
    // Wide enough for both, so the toggle goes: Days and Month answer the same
    // question at different zooms, and comparing them is the whole point of
    // having both. A control that hides one of two things you want to compare
    // is a control that exists only because the screen was too narrow.
    // Sideways, the week grid takes the Days list's place beside the month.
    //
    // The list exists because seven columns do not fit on a narrow screen —
    // given the width, the grid is strictly the better shape: same blocks,
    // same fortnight within reach, plus the arrangement, which is the one
    // thing a list of days cannot show. Keeping both would mean three panes
    // or a toggle, and a toggle is what the wide layout deleted.
    if (Layout.isWide(MediaQuery.sizeOf(context))) {
      return const Row(
        children: [
          Expanded(flex: 5, child: WeekScreen()),
          VerticalDivider(width: 1),
          Expanded(flex: 4, child: CalendarScreen()),
        ],
      );
    }

    // All three sit directly under the app bar and inset themselves, exactly
    // as every other screen does — there is no longer a strip in between for
    // them to start below.
    return IndexedStack(
      index: view,
      sizing: StackFit.expand,
      children: const [PlanScreen(), WeekScreen(), CalendarScreen()],
    );
  }
}

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
      // Named so a test can measure this list and not the month view, which
      // IndexedStack keeps alive in the tree beside it.
      key: const ValueKey('plan-days'),
      padding: EdgeInsets.only(
        top: 8 + glassTopInset(context),
        bottom: navBottomInset(context),
      ),
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
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).colorScheme.outline),
                ),
              )
            else
              for (final s in sessions)
                SessionTile(
                  session: s,
                  color: Color(
                    state.subjectFor(s.subjectId)?.colorValue ?? 0xFF4F46E5,
                  ),
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

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
          child: Row(
            children: [
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
            ],
          ),
        ),
        ...children,
      ],
    );
  }
}

/// Per-subject progress, which is the question students actually ask:
/// "am I on track for Physics?"
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  bool _showArchive = false;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    if (state.subjects.isEmpty) {
      return const EmptyState(
        icon: Icons.track_changes_outlined,
        title: 'No progress yet',
        message: 'Add a subject to start tracking.',
      );
    }

    // Past exams fold away here exactly as they do on Subjects — "archived"
    // being nothing more than "the exam has been", so the two screens cannot
    // disagree about which subjects are over.
    final active = state.activeSubjects;
    final archived = state.archivedSubjects;

    // The headline counts what is still ahead. Including a finished subject
    // would hold the percentage down for good over work that can no longer be
    // done, which reads as failure rather than as history.
    final total = active.fold(
      0,
      (a, s) =>
          a + state.topicsFor(s.id).fold(0, (b, t) => b + t.estimatedMinutes),
    );
    final done = active.fold(
      0,
      (a, s) =>
          a + state.topicsFor(s.id).fold(0, (b, t) => b + t.completedMinutes),
    );

    // Capped rather than stretched: a progress card three feet wide is not
    // more informative, only harder to read across.
    return ReadableColumn(
      child: ListView(
        padding: EdgeInsets.only(
        top: 8 + glassTopInset(context),
        bottom: navBottomInset(context),
      ),
        children: [
          _OverallCard(done: done, total: total, streak: state.streak),
          const _CalibrationSection(),
          for (final subject in active)
            _SubjectProgress(
              subject: subject,
              topics: state.topicsFor(subject.id),
              prefs: state.prefs,
            ),

          if (archived.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Archive · ${archived.length}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                subtitle: const Text('Subjects whose exam has passed'),
                trailing: Icon(
                  _showArchive ? Icons.expand_less : Icons.expand_more,
                ),
                onTap: () => setState(() => _showArchive = !_showArchive),
              ),
            ),
            if (_showArchive)
              for (final subject in archived)
                _SubjectProgress(
                  subject: subject,
                  topics: state.topicsFor(subject.id),
                  prefs: state.prefs,
                ),
          ],

          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              'Tap a subject to see its topics.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline),
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows any calibration recommendations the log currently supports.
///
/// A separate widget so the FutureBuilder for the log query doesn't rebuild
/// the whole Progress screen when the state changes. Silent when there is
/// nothing to suggest — no evidence, no card.
class _CalibrationSection extends StatelessWidget {
  const _CalibrationSection();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return FutureBuilder<List<CalibrationSuggestion>>(
      future: state.calibrationSuggestions(),
      builder: (context, snap) {
        final suggestions = snap.data ?? const [];
        if (suggestions.isEmpty) return const SizedBox.shrink();
        return Column(
          children: [
            for (final s in suggestions)
              _CalibrationCard(suggestion: s, state: state),
          ],
        );
      },
    );
  }
}

class _CalibrationCard extends StatelessWidget {
  const _CalibrationCard({required this.suggestion, required this.state});

  final CalibrationSuggestion suggestion;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subject = state.subjectFor(suggestion.subjectId);
    if (subject == null) return const SizedBox.shrink();

    final unitLabel = switch (suggestion.unit) {
      EffortUnit.pages => 'page',
      EffortUnit.problems => 'problem',
      EffortUnit.minutes => 'minute',
    };
    final delta = (suggestion.relativeChange * 100).abs().round();
    final direction = suggestion.isFaster ? 'faster' : 'slower';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text('Estimate learned', style: theme.textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Your ${subject.name} $unitLabel takes '
                '${suggestion.recommendedRate.toStringAsFixed(1)} min instead '
                'of ${suggestion.currentRate.toStringAsFixed(1)}. '
                '$delta% $direction than estimated, based on '
                '${suggestion.sampleCount} sessions.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Updates ${suggestion.affectedTopicIds.length} topic'
                '${suggestion.affectedTopicIds.length == 1 ? '' : 's'} — '
                'progress is preserved.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonal(
                  // See SessionTile's Done button: the theme's amber fill
                  // reaches the tonal variant, so a genuinely secondary
                  // action asks for the soft container back.
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    foregroundColor: theme.colorScheme.onSecondaryContainer,
                  ),
                  onPressed: () async {
                    await state.applyCalibration(suggestion);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            'Updated ${suggestion.affectedTopicIds.length} '
                            '${subject.name} topic'
                            '${suggestion.affectedTopicIds.length == 1 ? '' : 's'}.',
                          ),
                          duration: const Duration(seconds: 4),
                        ),
                      );
                    }
                  },
                  child: const Text('Update estimates'),
                ),
              ),
            ],
          ),
        ),
      ),
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
                Text(
                  '${(pct * 100).round()}%',
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(width: 10),
                // Expanded rather than a plain Text plus Spacer. A Spacer does
                // not stop a Row overflowing — inflexible children are laid
                // out first at their natural size and the spacer simply gets
                // nothing left — so at a large system font scale this line
                // ran off the right of the card. Expanded both absorbs the
                // slack the Spacer used to and lets the label wrap when there
                // is none.
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'of everything covered',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                if (streak > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.local_fire_department,
                          size: 18,
                          color: theme.colorScheme.tertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$streak d',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.tertiary,
                          ),
                        ),
                      ],
                    ),
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
  const _SubjectProgress({
    required this.subject,
    required this.topics,
    required this.prefs,
  });

  final Subject subject;
  final List<Topic> topics;

  /// The study window, which is what turns "the exam is at 9am" into "today
  /// is worth a fifth of a day".
  final Prefs prefs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = topics.fold(0, (a, t) => a + t.estimatedMinutes);
    final done = topics.fold(0, (a, t) => a + t.completedMinutes);
    final progress = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    final now = DateTime.now();
    final deadline = examLabel(subject, now);

    // The question a student actually has: at this rate, do I finish in time?
    // Asked through Subject.examDemand so that every screen answers it the
    // same way — including the case where the answer is "it doesn't".
    final remaining = total - done;
    final demand = subject.examDemand(
      remainingMinutes: remaining,
      from: now,
      studyMinutesPerDay: prefs.windowMinutes,
      windowStartMinute: prefs.dayStartMinute,
      windowEndMinute: prefs.dayEndMinute,
    );
    // A past exam needs no advice: "exam passed" already says everything, and
    // adding "won't fit" to it would be piling on.
    final impossible = demand.impossible && !subject.examHasPassed(now);
    final perDay = demand.perDay;

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
              // The name takes the whole line and wraps. It used to share the
              // row with the deadline, which collided the moment a subject was
              // called something like "Data Structures and Algorithms" — the
              // name is the one string here the app does not control.
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Color(subject.colorValue),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      subject.name,
                      style: theme.textTheme.titleMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
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
              // Deadline and demand read as one thought, on a line of their
              // own that is free to wrap. Both are about time remaining.
              if (deadline != null || perDay != null || impossible) ...[
                const SizedBox(height: 4),
                Text(
                  [
                    ?deadline,
                    if (perDay != null)
                      'needs ${formatMinutes(perDay)} a day to finish in time',
                    if (impossible) "won't fit before the exam",
                  ].join('  ·  '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: impossible
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ),
              ],
              if (remaining == 0 && total > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Covered. Reviews continue.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
