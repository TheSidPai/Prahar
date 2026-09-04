import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/format.dart';
import '../domain/preferences.dart';
import '../domain/schedule.dart';
import '../domain/today_focus.dart';
import '../state/app_state.dart';
import 'brand.dart';
import 'glass.dart';
import 'how_it_works.dart';
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

    if (state.subjects.isEmpty) return const _FirstRun();

    final now = DateTime.now();
    final focus = focusFor(
      remaining: state.todaySessions,
      anythingLogged: state.todayLog.isNotEmpty,
      nowMinuteOfDay: now.hour * 60 + now.minute,
    );

    final rest = state.todaySessions
        .where((s) => s.id != focus.session?.id)
        .toList()
      ..sort((a, b) => a.startMinuteOfDay.compareTo(b.startMinuteOfDay));

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
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

        if (rest.isNotEmpty) ...[
          const SizedBox(height: 26),
          _SectionLabel('Then'),
          for (final s in rest)
            _RailRow(
              session: s,
              color: Color(
                  state.subjectFor(s.subjectId)?.colorValue ?? 0xFF4F46E5),
              onTap: () => _openTimer(s),
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
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
          ),
        ),
      ],
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
                child: Text(formatDateFull(state.today),
                    style: theme.textTheme.titleLarge),
              ),
              if (state.streak > 0)
                Row(children: [
                  Icon(Icons.local_fire_department,
                      size: 18, color: theme.colorScheme.tertiary),
                  const SizedBox(width: 4),
                  Text(
                    '${state.streak}',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: theme.colorScheme.tertiary),
                  ),
                ]),
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
    final glass = state.prefs.materialChoice == MaterialChoice.glass;
    final session = focus.session;

    final content = session == null
        ? _emptyBody(theme)
        : _blockBody(context, theme, session);

    final panel = glass
        ? GlassSurface(
            borderRadius: BorderRadius.circular(24),
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            child: content,
          )
        : Container(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: content,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: panel,
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
          done
              ? "That's everything."
              : 'No study time today.',
          style: theme.textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(
          done
              ? '${formatMinutes(state.doneMinutesToday)} done. '
                  'Tomorrow is already planned.'
              : 'Add time in Settings, or a subject to study.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _blockBody(
      BuildContext context, ThemeData theme, StudySession session) {
    final running = focus.kind == FocusKind.now;
    final subjectColour =
        Color(state.subjectFor(session.subjectId)?.colorValue ?? 0xFF4F46E5);

    final kicker = running
        ? 'NOW · ${formatClock(session.startMinuteOfDay)}'
            '–${formatClock(session.startMinuteOfDay + session.durationMinutes)}'
        : focus.minutesUntilStart == 0
            ? 'UP NEXT · DUE'
            : 'UP NEXT · IN ${formatMinutes(focus.minutesUntilStart).toUpperCase()}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: subjectColour, shape: BoxShape.circle),
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
            Text('REVIEW',
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.4,
                  color: theme.colorScheme.onSurfaceVariant,
                )),
        ]),
        const SizedBox(height: 14),
        Text(
          session.topicTitle,
          style: theme.textTheme.headlineSmall?.copyWith(height: 1.15),
        ),
        const SizedBox(height: 6),
        Text(
          '${session.subjectName} · ${formatMinutes(session.durationMinutes)}'
          '${running ? ' · ${formatMinutes(focus.minutesLeft)} left' : ''}',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        Row(children: [
          FilledButton.icon(
            onPressed: onStart,
            icon: const Icon(Icons.play_arrow, size: 20),
            label: const Text('Start focus'),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => confirmSkip(context, state, session),
            child: const Text('Skip'),
          ),
          TextButton(
            onPressed: () => confirmDone(context, state, session),
            child: const Text('Done'),
          ),
        ]),
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

/// A later block: one line, no card, no buttons. Everything about it is
/// context for the hero above.
class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.session,
    required this.color,
    required this.onTap,
  });

  final StudySession session;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            SizedBox(
              width: 46,
              child: Text(
                formatClock(session.startMinuteOfDay),
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
                  Text(session.subjectName,
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              formatMinutes(session.durationMinutes),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
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
            child: Row(children: [
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
              Icon(_open ? Icons.expand_less : Icons.expand_more,
                  size: 20, color: theme.colorScheme.outline),
            ]),
          ),
        ),
        if (_open)
          for (final entry in log)
            LoggedTile(
              entry: entry,
              color: Color(widget.state
                      .subjectFor(entry.subjectId)
                      ?.colorValue ??
                  0xFF4F46E5),
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
  const _FirstRun();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 28, 20, 8),
          child: PraharLogo(markSize: 56),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
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
}
