import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/format.dart';
import '../domain/schedule.dart';
import '../domain/today_focus.dart';
import '../state/app_state.dart';
import 'brand.dart';
import 'glass.dart';
import 'how_it_works.dart';
import 'layout.dart';
import 'subjects_screen.dart';
import 'timer_screen.dart';
import 'widgets.dart';

/// Today, rebuilt around one question: what am I meant to be doing now?
///
/// Running alongside the original rather than replacing it, so the two can be
/// compared on a real day with real data before either is deleted.
///
/// The original renders every block as the same card — the one happening now
/// and the one at half past eight get identical weight — which is why it reads
/// as a generic list. Four moves here:
///
///   1. One block is the answer, at hero size, with one primary action.
///   2. The rest is a compact rail, not cards. Three upcoming blocks cost
///      about 120px here against 260px of cards, so the hero is nearly free.
///   3. Finished work collapses to a line. It is reassurance, not something
///      to read.
///   4. The day header stops being a panel, which frees the screen's single
///      glass surface for the hero.
///
/// What does *not* move: the battery and exact-alarm warnings stay above
/// everything. A beautiful hero card for a block whose reminder will never
/// fire is a lie, and that has been true of this app since the first device
/// test.
class TodayEditorialScreen extends StatefulWidget {
  const TodayEditorialScreen({super.key});

  @override
  State<TodayEditorialScreen> createState() => _TodayEditorialScreenState();
}

class _TodayEditorialScreenState extends State<TodayEditorialScreen> {
  Timer? _minute;

  /// The rail row currently showing its actions. One at a time: two open rows
  /// is a list of half-cards, and the point of the rail is that it stays quiet
  /// until spoken to.
  String? _openRow;

  @override
  void initState() {
    super.initState();
    // "Starts in 14 min" is a lie within sixty seconds unless something
    // repaints it. One rebuild a minute is cheap; the old screen computed
    // "now" once per build and could sit stale for an hour.
    _minute = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _minute?.cancel();
    super.dispose();
  }

  void _openTimer(StudySession session) {
    Navigator.push(
      context,
      MaterialPageRoute<int>(builder: (_) => TimerScreen(session: session)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);

    // With a glass app bar the body extends behind it, so the list has to
    // start below the status bar plus the bar's own height or the date would
    // spend its life underneath the wordmark. Every screen does this now, so
    // the rule lives in `glassTopInset` rather than here.
    final topInset = glassTopInset(context);

    if (state.subjects.isEmpty) return _FirstRun(topInset: topInset);

    final now = DateTime.now();
    final focus = focusFor(
      remaining: state.todaySessions,
      anythingLogged: state.todayLog.isNotEmpty,
      nowMinuteOfDay: now.hour * 60 + now.minute,
    );

    final rest =
        state.todaySessions.where((s) => s.id != focus.session?.id).toList()
          ..sort((a, b) => a.startMinuteOfDay.compareTo(b.startMinuteOfDay));

    // What the day is about, and what is around it. The split exists because
    // the two answer different questions, which is also why they separate so
    // cleanly when there is room for two columns.
    final lead = <Widget>[
      _DayHeader(state: state),
      if (!state.batteryExempt) BatteryWarning(state: state),
      if (!state.exactAlarmsAllowed) const ExactAlarmWarning(),
      // Condensed while the plan fits, full-throated when it does not.
      if (state.feasibility != null)
        FeasibilityBanner(
          feasibility: state.feasibility!,
          condensed: state.feasibility!.fits,
        ),
      const SizedBox(height: 18),
      _Hero(
        focus: focus,
        state: state,
        onStart: focus.session == null
            ? null
            : () => _openTimer(focus.session!),
      ),
    ];

    final around = <Widget>[
      if (rest.isNotEmpty) ...[
        const SizedBox(height: 26),
        _SectionLabel('Then'),
        for (final s in rest)
          _RailRow(
            session: s,
            color: Color(
              state.subjectFor(s.subjectId)?.colorValue ?? 0xFF4F46E5,
            ),
            open: _openRow == s.id,
            onToggle: () =>
                setState(() => _openRow = _openRow == s.id ? null : s.id),
            onStart: () {
              setState(() => _openRow = null);
              _openTimer(s);
            },
            onDone: () {
              setState(() => _openRow = null);
              confirmDone(context, state, s);
            },
            onSkip: () {
              setState(() => _openRow = null);
              confirmSkip(context, state, s);
            },
          ),
      ],
      if (state.todayLog.isNotEmpty) ...[
        const SizedBox(height: 26),
        _DoneStrip(state: state),
      ],
      const SizedBox(height: 20),
      Center(
        child: Text(
          'Tap a block to start a focus timer.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ),
    ];

    // Sideways, the hero and its context sit beside each other instead of the
    // context being pushed off the bottom of a 410dp-tall screen. Two scroll
    // views rather than one: the rail is long and the hero is not, and tying
    // them together would scroll the answer off screen to reach the list.
    if (Layout.isWide(MediaQuery.sizeOf(context))) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: ListView(
              padding: EdgeInsets.only(top: topInset, bottom: 24),
              children: lead,
            ),
          ),
          Expanded(
            flex: 4,
            child: ListView(
              padding: EdgeInsets.only(top: topInset + 12, bottom: 24),
              children: around,
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: EdgeInsets.only(top: topInset, bottom: 100),
      children: [...lead, ...around],
    );
  }
}

/// Date, the day's progress, and the streak. Plain text on the page rather
/// than a card: it is a masthead, not an object.
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = state.doneMinutesToday;
    final planned = state.plannedMinutesToday;
    final progress = planned == 0 ? 0.0 : (done / planned).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  formatDateFull(state.today),
                  style: theme.textTheme.titleLarge,
                ),
              ),
              if (state.streak > 0)
                Row(
                  children: [
                    Icon(
                      Icons.local_fire_department,
                      size: 18,
                      color: theme.colorScheme.tertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${state.streak}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.tertiary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: progress, minHeight: 5),
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

/// The one block the screen is about.
class _Hero extends StatelessWidget {
  const _Hero({required this.focus, required this.state, this.onStart});

  final TodayFocus focus;
  final AppState state;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = focus.session;

    final content = session == null
        ? _emptyBody(theme)
        : _blockBody(context, theme, session);

    // The hero answers to Settings > Cards in both materials. That logic now
    // lives in StyledPanel, because Look's header needs exactly the same
    // surface and a second hand-rolled one drifted immediately.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: StyledPanel(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: content,
      ),
    );
  }

  /// A finished day and an empty one read very differently, and saying the
  /// wrong one is worse than saying nothing.
  Widget _emptyBody(ThemeData theme) {
    final done = focus.kind == FocusKind.allDone;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          done ? 'DONE FOR TODAY' : 'NOTHING SCHEDULED',
          style: theme.textTheme.labelSmall?.copyWith(
            letterSpacing: 1.6,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          done ? "That's everything." : 'No study time today.',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          done
              ? '${formatMinutes(state.doneMinutesToday)} done. '
                    'Tomorrow is already planned.'
              : 'Add time in Settings, or a subject to study.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _blockBody(
    BuildContext context,
    ThemeData theme,
    StudySession session,
  ) {
    final running = focus.kind == FocusKind.now;
    final subjectColour = Color(
      state.subjectFor(session.subjectId)?.colorValue ?? 0xFF4F46E5,
    );

    final kicker = running
        ? 'NOW · ${formatClock(session.startMinuteOfDay)}'
              '–${formatClock(session.startMinuteOfDay + session.durationMinutes)}'
        : focus.minutesUntilStart == 0
        ? 'UP NEXT · DUE'
        : 'UP NEXT · IN ${formatMinutes(focus.minutesUntilStart).toUpperCase()}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: subjectColour,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                kicker,
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w700,
                  // tertiary is amber-as-text, already brightness-aware.
                  color: running
                      ? theme.colorScheme.tertiary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (session.isReview)
              Text(
                'REVIEW',
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.4,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          session.topicTitle,
          style: theme.textTheme.headlineSmall?.copyWith(height: 1.15),
        ),
        const SizedBox(height: 6),
        Text(
          '${session.subjectName} · ${formatMinutes(session.durationMinutes)}'
          '${running ? ' · ${formatMinutes(focus.minutesLeft)} left' : ''}',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 20),
        // Wrap, not Row: three buttons and a Spacer overflowed a 411dp phone
        // by 48px, and the hero is exactly where a wide subject name or a
        // narrow pane will squeeze hardest. Wrapping drops Skip and Done onto
        // a second line rather than clipping them, and the grouping keeps
        // those two together wherever they land.
        Wrap(
          spacing: 8,
          runSpacing: 4,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: onStart,
              icon: const Icon(Icons.play_arrow, size: 20),
              label: const Text('Start focus'),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => confirmSkip(context, state, session),
                  child: const Text('Skip'),
                ),
                TextButton(
                  onPressed: () => confirmDone(context, state, session),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 1.4,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }
}

/// A later block: one compact line that opens in place when you touch it.
///
/// It has to be *actionable* — plenty of work gets finished or abandoned out
/// of order, and a row you can only look at is a row that sends you somewhere
/// else to act. But two visible buttons per row is exactly what makes every
/// block look equally important, which is the thing this screen exists to
/// stop.
///
/// So the actions are not on the row and not in a menu either: the row itself
/// unfolds. One tap expands it, the actions fade in beneath a hairline, a
/// second tap folds it away, and opening one closes any other. Nothing leaves
/// the page, nothing floats above it, and the row you touched stays exactly
/// where it was under your finger.
///
/// The card comes from the theme, so it wears whichever style is chosen in
/// Settings > Cards — including Open, where it correctly becomes a bare line.
class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.session,
    required this.color,
    required this.open,
    required this.onToggle,
    required this.onStart,
    required this.onDone,
    required this.onSkip,
  });

  final StudySession session;
  final Color color;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onStart;
  final VoidCallback onDone;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onToggle,
          // AnimatedSize measures the child, so the card grows and shrinks
          // with the reveal rather than snapping to its open height.
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 46,
                        child: Text(
                          formatClock(session.startMinuteOfDay),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Container(
                        width: 3,
                        height: 26,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              session.topicTitle,
                              style: theme.textTheme.bodyLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              session.subjectName,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        formatMinutes(session.durationMinutes),
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(width: 6),
                      // The only affordance on the line, and it turns to point
                      // at what it just revealed.
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        child: Icon(
                          Icons.keyboard_arrow_down,
                          size: 20,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                if (open)
                  _RailActions(
                    onStart: onStart,
                    onDone: onDone,
                    onSkip: onSkip,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The revealed actions: three, evenly weighted by space but not by emphasis.
/// Start focus carries the accent because starting is what this screen wants
/// you to do; Done and Skip are quiet, because they are admissions rather than
/// intentions.
class _RailActions extends StatelessWidget {
  const _RailActions({
    required this.onStart,
    required this.onDone,
    required this.onSkip,
  });

  final VoidCallback onStart;
  final VoidCallback onDone;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget action({
      required IconData icon,
      required String label,
      required VoidCallback onTap,
      bool accented = false,
    }) {
      final colour = accented
          ? theme.colorScheme.tertiary
          : theme.colorScheme.onSurfaceVariant;
      return Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: colour),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colour,
                    fontWeight: accented ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        // Inset so the divider reads as a fold in the card rather than a cut
        // across it.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Divider(
            height: 1,
            thickness: 1,
            color: theme.colorScheme.outlineVariant,
          ),
        ),
        Row(
          children: [
            action(
              icon: Icons.play_arrow_rounded,
              label: 'Focus',
              onTap: onStart,
              accented: true,
            ),
            action(icon: Icons.check_rounded, label: 'Done', onTap: onDone),
            action(icon: Icons.redo_rounded, label: 'Skip', onTap: onSkip),
          ],
        ),
      ],
    );
  }
}

/// Finished work, one line deep until asked otherwise. The undo buttons live
/// inside, so nothing is lost by folding it away — but a done block is
/// reassurance, and reassurance does not need to occupy the screen.
class _DoneStrip extends StatefulWidget {
  const _DoneStrip({required this.state});

  final AppState state;

  @override
  State<_DoneStrip> createState() => _DoneStripState();
}

class _DoneStripState extends State<_DoneStrip> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final log = widget.state.todayLog;
    final done = log.where((e) => !e.wasSkipped).length;
    final skipped = log.length - done;
    final minutes = log.fold(0, (a, e) => a + e.actualMinutes);

    final summary = [
      if (done > 0) '$done done',
      if (skipped > 0) '$skipped skipped',
      if (minutes > 0) formatMinutes(minutes),
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Text(
                  'BEHIND YOU',
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(summary, style: theme.textTheme.bodySmall),
                ),
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: theme.colorScheme.outline,
                ),
              ],
            ),
          ),
        ),
        if (_open)
          for (final entry in log)
            LoggedTile(
              entry: entry,
              color: Color(
                widget.state.subjectFor(entry.subjectId)?.colorValue ??
                    0xFF4F46E5,
              ),
              onUndo: () async {
                await widget.state.undoLogged(entry);
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
      ],
    );
  }
}

/// Unchanged from the original screen: the one moment a new user meets the app
/// cold is not the place to experiment.
class _FirstRun extends StatelessWidget {
  const _FirstRun({required this.topInset});

  final double topInset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Centred in whatever height is left, and still scrollable when there is
    // not enough of it — a landscape phone has about 350dp here.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.only(top: topInset, bottom: 90),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - topInset - 90).clamp(
              0.0,
              double.infinity,
            ),
          ),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // The flat mark, not the filled tile. The gradient tile is
                  // the launcher icon — showing it inside the app is showing
                  // the user the thing they just tapped, and it sits on the
                  // page like a sticker. The drawn mark belongs to the page.
                  const PraharMark(size: 84),
                  const SizedBox(height: 22),
                  Text(
                    'Prahar',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Held to a readable measure and centred under the wordmark,
                  // rather than running the full width of the screen where the
                  // second line starts a long way from where the first ended.
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: Text(
                      'A study planner that tells you the truth about '
                      'whether your plan is possible.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        height: 1.45,
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
                  FilledButton.icon(
                    onPressed: () => showSubjectSheet(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add your first subject'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                    ),
                  ),
                  const SizedBox(height: 6),
                  // The guide opens as its own page. It used to be inlined
                  // here, and being a ListView inside a ListView it was an
                  // unbounded-height error — which a release build draws as a
                  // silent black rectangle, so the whole lower half of the
                  // first screen was a rendering failure nobody could see.
                  TextButton(
                    onPressed: () => HowItWorks.open(context),
                    child: const Text('How Prahar works'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
