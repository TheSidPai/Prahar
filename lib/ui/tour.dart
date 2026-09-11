import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../domain/format.dart';
import '../domain/tour.dart';
import '../state/app_state.dart';
import 'spotlight.dart';
import 'widgets.dart';

/// The things the first-run tour points at.
enum TourTargetId {
  navigation,
  subjectsTab,
  addSubject,
  firstSubject,
  addTopic,
  today,
  planTab,
}

/// Marks a widget the tour can point at.
///
/// With a null [id] it marks nothing, so a list can mark its first row only
/// without the rows being different kinds of widget.
///
/// Each marker owns its own GlobalKey rather than sharing one per target. The
/// same target can briefly exist twice, on a page being pushed and the page
/// under it, and two widgets holding one GlobalKey is a crash.
class TourTarget extends StatefulWidget {
  const TourTarget({super.key, required this.id, required this.child});

  final TourTargetId? id;
  final Widget child;

  @override
  State<TourTarget> createState() => _TourTargetState();
}

class _TourTargetState extends State<TourTarget> {
  final _key = GlobalKey();

  /// Whether this widget's page is the one on top. False while a sheet or a
  /// dialog is open over it, or another page has been pushed on top of it.
  bool _onTop = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Depending on the route is what brings us back here when a sheet opens
    // over the page or closes again.
    _onTop = ModalRoute.of(context)?.isCurrent ?? true;
    TourTargets.instance._update(widget.id, this);
  }

  @override
  void didUpdateWidget(TourTarget old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      TourTargets.instance._remove(old.id, this);
      TourTargets.instance._update(widget.id, this);
    }
  }

  @override
  void dispose() {
    TourTargets.instance._remove(widget.id, this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      KeyedSubtree(key: _key, child: widget.child);
}

/// Every mounted [TourTarget], so the tour can find what it points at.
class TourTargets extends ChangeNotifier {
  TourTargets._();

  static final instance = TourTargets._();

  final _targets = <TourTargetId, List<_TourTargetState>>{};
  bool _pending = false;

  /// The key of the [id] target on the page that is on top, if there is one.
  GlobalKey? find(TourTargetId id) {
    final list = _targets[id];
    if (list == null) return null;
    for (final t in list.reversed) {
      if (t.mounted && t._onTop) return t._key;
    }
    return null;
  }

  void _update(TourTargetId? id, _TourTargetState t) {
    if (id != null) {
      final list = _targets.putIfAbsent(id, () => []);
      if (!list.contains(t)) list.add(t);
    }
    _changed();
  }

  void _remove(TourTargetId? id, _TourTargetState t) {
    if (id == null) return;
    _targets[id]?.remove(t);
    _changed();
  }

  /// Said after the frame, never during it. Targets come and go while the tree
  /// is being built, and the host listening to this is part of that tree.
  void _changed() {
    if (_pending) return;
    _pending = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      notifyListeners();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }
}

/// Draws the first-run tour over the whole app.
///
/// It sits above the navigator, in `MaterialApp.builder`, so the tour stays on
/// screen when a page is pushed: adding a topic on a phone happens on the
/// subject's own page, one push away from where the tour found the subject.
class TourHost extends StatefulWidget {
  const TourHost({super.key, required this.child});

  final Widget child;

  @override
  State<TourHost> createState() => _TourHostState();
}

class _TourHostState extends State<TourHost> {
  @override
  void initState() {
    super.initState();
    TourTargets.instance.addListener(_targetsChanged);
  }

  @override
  void dispose() {
    TourTargets.instance.removeListener(_targetsChanged);
    super.dispose();
  }

  void _targetsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final step = state.tourStep;
    final overlay = step == null ? null : _overlayFor(step, state);

    // The app stays the first child whether or not the tour is showing, so
    // the tour coming and going never rebuilds the navigator and loses the
    // pages on it.
    return Stack(fit: StackFit.expand, children: [widget.child, ?overlay]);
  }

  Widget? _overlayFor(TourStep step, AppState state) {
    final targets = TourTargets.instance;
    final active = state.activeSubjects;
    final subject = active.isEmpty ? null : active.first;

    final GlobalKey? target;
    final SpotlightStep spot;
    switch (step) {
      case TourStep.welcome:
        target = null;
        spot = const SpotlightStep(
          title: 'Welcome to Prahar',
          body:
              'Add your subjects and exam dates, and Prahar plans each day '
              'for you. It reminds you as each study block starts.',
          nextLabel: 'Show me around',
          showMark: true,
        );
      case TourStep.navigation:
        target = targets.find(TourTargetId.navigation);
        spot = SpotlightStep(
          target: target,
          body: state.subjects.isEmpty
              ? 'These five tabs are the whole app. Start with Subjects.'
              : 'These five tabs are the whole app.',
        );
      case TourStep.openSubjects:
        target = targets.find(TourTargetId.subjectsTab);
        spot = SpotlightStep(
          target: target,
          advance: SpotlightAdvance.action,
          body: subject == null
              ? 'Tap Subjects.'
              : 'Tap Subjects to carry on setting up.',
        );
      case TourStep.addSubject:
        target = targets.find(TourTargetId.addSubject);
        spot = SpotlightStep(
          target: target,
          advance: SpotlightAdvance.action,
          title: 'Add your first subject',
          body: 'Give it a name and the date of its exam, then tap Save.',
        );
      case TourStep.subject:
        target = targets.find(TourTargetId.firstSubject);
        spot = SpotlightStep(
          target: target,
          title: subject?.name,
          body: subject?.examDate == null
              ? 'It has no exam date yet, so it is planned after anything '
                    'that has one. You can add a date from its page.'
              : 'Its exam date decides how much Prahar plans for it each day.',
        );
      case TourStep.addTopic:
        // On a phone the button is on the subject's own page, so until that
        // is open, the stop points at the row that opens it.
        final button = targets.find(TourTargetId.addTopic);
        target = button ?? targets.find(TourTargetId.firstSubject);
        spot = button != null
            ? SpotlightStep(
                target: button,
                advance: SpotlightAdvance.action,
                title: 'Add a topic',
                body:
                    'A chapter works well. Enter its page count and Prahar '
                    'works out the time.',
              )
            : SpotlightStep(
                target: target,
                advance: SpotlightAdvance.action,
                body: 'Open it to add its first topic.',
              );
      case TourStep.reminders:
        target = null;
        spot = SpotlightStep(
          title: 'Turn on reminders',
          body:
              'Prahar reminds you as each study block starts. Android needs '
              'a few things allowed first.',
          nextLabel: 'Continue',
          extra: _ReminderSetup(state: state),
        );
      case TourStep.today:
        target = targets.find(TourTargetId.today);
        spot = SpotlightStep(
          target: target,
          // Set up late at night, or against an exam that is today, there is
          // nothing to point at on the card, and saying "study this" over an
          // empty one would be wrong.
          body: state.todaySessions.isEmpty
              ? 'This card shows what to study now. Nothing more is planned '
                    'for today.'
              : 'This is what to study now. Tap Start focus to begin, and '
                    'Done when you finish.',
        );
      case TourStep.plan:
        target = targets.find(TourTargetId.planTab);
        spot = SpotlightStep(
          target: target,
          body: 'Tap Plan any time to see the days ahead.',
          nextLabel: 'Got it',
        );
    }

    // A stop that waits for a tap has nothing to show without the thing to
    // tap. That is what happens while a sheet is open over it: the tour steps
    // aside, and comes back when the sheet closes, saved or not.
    if (step.waitsForTap && target == null) return null;

    return Positioned.fill(
      child: SpotlightOverlay(
        // A fresh overlay per stop, so each one fades in rather than the
        // window jumping from one target to the next.
        key: ValueKey((step, target)),
        step: spot,
        onNext: step == TourStep.reminders
            ? state.finishTourReminders
            : step.isRead
            ? () => state.tourNext(step)
            : null,
        onSkip: state.skipTour,
      ),
    );
  }
}

/// The reminders stop: each thing Android needs allowed, with its own button.
///
/// The same four things Settings > Notifications offers, in the order they
/// matter, at the one moment a student is paying attention to setting up.
/// Nothing here is required to carry on. Continue asks for notifications if
/// that row was never used, since without them nothing else on the card
/// matters.
class _ReminderSetup extends StatefulWidget {
  const _ReminderSetup({required this.state});

  final AppState state;

  @override
  State<_ReminderSetup> createState() => _ReminderSetupState();
}

class _ReminderSetupState extends State<_ReminderSetup> {
  /// When the test reminder is due, once one has been sent.
  DateTime? _testAt;

  /// Whether the autostart screen was opened. Android reports nothing about
  /// the setting itself, so having been there is all that can be shown.
  bool _autostartOpened = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final gate = state.backgroundGate;
    final testAt = _testAt;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SetupRow(
          key: const ValueKey('tour-allow-notifications'),
          done: state.remindersAsked && state.exactAlarmsAllowed,
          title: 'Notifications',
          detail:
              'Android may ask twice: to show reminders, and to send them on '
              'time.',
          action: 'Allow',
          onPressed: state.requestReminderPermissions,
        ),
        _SetupRow(
          key: const ValueKey('tour-allow-background'),
          done: state.batteryExempt,
          title: 'Run in the background',
          detail: 'So Android does not freeze Prahar before a reminder is due.',
          action: 'Allow',
          onPressed: state.requestBatteryExemption,
        ),
        // Only on phones that have such a screen. Stock Android has none, and
        // a row sending someone to look for a setting that does not exist is
        // worse than no row.
        if (gate != null)
          _SetupRow(
            key: const ValueKey('tour-autostart'),
            done: _autostartOpened,
            title: gate.rowTitle,
            detail: gate.explanation,
            action: 'Open',
            onPressed: () async {
              final outcome = await state.openAutostartSettings();
              if (!context.mounted) return;
              setState(() => _autostartOpened = true);
              autostartFallbackHint(context, outcome, gate);
            },
          ),
        _SetupRow(
          key: const ValueKey('tour-test-reminder'),
          done: testAt != null,
          title: 'Send a test reminder',
          detail: testAt == null
              ? 'It arrives in a minute, so you can see one work.'
              : 'Due at ${formatClock(testAt.hour * 60 + testAt.minute)}. '
                    'Lock the phone and wait.',
          action: testAt == null ? 'Send' : 'Again',
          repeatable: true,
          onPressed: () async {
            try {
              final when = await state.notifier.scheduleTest();
              if (mounted) setState(() => _testAt = when);
            } catch (e) {
              debugPrint('Prahar: could not send a test reminder: $e');
            }
          },
        ),
      ],
    );
  }
}

class _SetupRow extends StatelessWidget {
  const _SetupRow({
    super.key,
    required this.done,
    required this.title,
    required this.detail,
    required this.action,
    required this.onPressed,
    this.repeatable = false,
  });

  final bool done;
  final String title;
  final String detail;
  final String action;
  final VoidCallback onPressed;

  /// Keeps its button once done. Only the test reminder, which is worth
  /// sending again after changing a setting.
  final bool repeatable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              size: 20,
              // Indigo for something taken care of. Amber stays on buttons.
              color: done
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            ),
          ),
          const SizedBox(width: 10),
          // Expanded, so a large font wraps the words rather than pushing the
          // button off the card.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (!done || repeatable)
            TextButton(onPressed: onPressed, child: Text(action)),
        ],
      ),
    );
  }
}
