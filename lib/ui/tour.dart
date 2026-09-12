import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../domain/format.dart';
import '../domain/tour.dart';
import '../state/app_state.dart';
import 'spotlight.dart';
import 'widgets.dart';

/// The things the tours point at.
enum TourTargetId {
  navigation,
  planTab,
  progressTab,
  addSubject,
  firstSubject,
  today,
  focus,
  skipBlock,
  doneBlock,
  laterBlocks,
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

/// Pulses one tab's icon while the tabs stop is showing, each tab a beat after
/// the one before, so "these five tabs" is shown as well as said. Only the
/// icon moves; the selected tab's pill stays still.
class TourTabPulse extends StatefulWidget {
  const TourTabPulse({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<TourTabPulse> createState() => _TourTabPulseState();
}

class _TourTabPulseState extends State<TourTabPulse>
    with SingleTickerProviderStateMixin {
  static const _periodMs = 3400.0;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3400),
  );

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final on = context.select<AppState, bool>(
      (s) => s.tourStop == TourStop.tabs,
    );
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (on && !still) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else if (_pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
    return AnimatedBuilder(
      animation: _pulse,
      child: widget.child,
      builder: (context, child) {
        final t =
            ((_pulse.value * _periodMs - widget.index * 140) % _periodMs) /
            _periodMs;
        final scale = t < 0.09
            ? 1 + 0.2 * (t / 0.09)
            : t < 0.28
            ? 1.2 - 0.2 * ((t - 0.09) / 0.19)
            : 1.0;
        return Transform.scale(scale: scale, child: child);
      },
    );
  }
}

/// Draws the tours over the whole app.
///
/// It sits above the navigator, in `MaterialApp.builder`, so a tour stays up
/// whatever page is showing. One overlay serves every stop of every tour, which
/// is what lets the window slide from one stop to the next.
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
    final stop = state.tourStop;
    final overlay = stop == null
        ? null
        : SpotlightOverlay(
            key: const ValueKey('tour-overlay'),
            step: _stepFor(stop, state),
            stepIndex: state.tourIndex,
            stepCount: state.tourLength,
            onNext: state.tourNext,
            onBack: state.tourIndex == 0 ? null : state.tourBack,
            onSkip: state.skipTour,
          );

    // The app stays the first child whether or not a tour is showing, so a
    // tour coming and going never rebuilds the navigator under it.
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: overlay ?? const SizedBox.shrink(key: ValueKey('no-tour')),
          ),
        ),
      ],
    );
  }

  SpotlightStep _stepFor(TourStop stop, AppState state) {
    final t = TourTargets.instance;
    final last = state.tourIndex == state.tourLength - 1;
    final hasSubject = state.subjects.isNotEmpty;

    switch (stop) {
      case TourStop.welcome:
        return const SpotlightStep(
          title: 'Welcome to Prahar',
          body:
              'Add your subjects and exam dates, and Prahar plans each day for '
              'you.',
          nextLabel: 'Show me around',
          showMark: true,
        );
      case TourStop.tabs:
        return SpotlightStep(
          target: t.find(TourTargetId.navigation),
          awaitTarget: true,
          body:
              "Five tabs, and that's the whole app: Today, Plan, Progress, "
              'Subjects, Settings.',
        );
      case TourStop.subjects:
        return hasSubject
            ? SpotlightStep(
                target:
                    t.find(TourTargetId.firstSubject) ??
                    t.find(TourTargetId.addSubject),
                awaitTarget: true,
                body:
                    'Each subject has its exam date, and the date decides how '
                    'much to do each day.',
              )
            : SpotlightStep(
                target: t.find(TourTargetId.addSubject),
                awaitTarget: true,
                body:
                    'Everything starts with a subject and its exam date. The '
                    'date decides how much to do each day.',
                extra: const _ExampleSubject(),
              );
      case TourStop.topics:
        return const SpotlightStep(
          body:
              'Each subject splits into topics, usually chapters. Enter the '
              'pages and Prahar works out the time.',
          extra: _ExampleTopics(),
        );
      case TourStop.today:
        return hasSubject
            ? SpotlightStep(
                target: t.find(TourTargetId.today),
                awaitTarget: true,
                body: state.todaySessions.isEmpty
                    ? 'This card shows what to study now. Nothing more is '
                          'planned for today.'
                    : 'This card shows what to study now.',
              )
            : const SpotlightStep(
                body:
                    "Once there's a plan, Today shows what to study now. Its "
                    'buttons are explained when your first block appears.',
                extra: _ExampleBlock(),
              );
      case TourStop.planProgress:
        return SpotlightStep(
          title: 'Plan and Progress',
          body:
              'Two tabs for when you want more than today: one looks ahead, '
              'one looks back.',
          awaitTarget: true,
          companions: [
            SpotlightCompanion(
              target: t.find(TourTargetId.planTab),
              icon: Icons.calendar_month_outlined,
              title: 'Plan',
              body: 'Every day ahead, by day, week or month.',
            ),
            SpotlightCompanion(
              target: t.find(TourTargetId.progressTab),
              icon: Icons.track_changes_outlined,
              title: 'Progress',
              body: "What's done, and what each exam still needs a day.",
            ),
          ],
        );
      case TourStop.reminders:
        return SpotlightStep(
          title: 'Turn on reminders',
          body:
              'Prahar reminds you as each study block starts. Android needs a '
              'few things allowed first.',
          extra: _ReminderSetup(state: state),
          nextLabel: last ? 'Done' : 'Next',
        );
      case TourStop.finish:
        return SpotlightStep(
          title: 'Ready to start',
          body:
              'Add your first subject and its exam date, and Prahar plans the '
              'rest.',
          extra: _FinishButton(onPressed: state.finishTourAddingSubject),
          nextLabel: 'Later',
          quietNext: true,
        );
      case TourStop.block:
        return SpotlightStep(
          target: t.find(TourTargetId.today),
          awaitTarget: true,
          title: 'Your first block',
          body: "This is what to study now. Here's what its buttons do.",
        );
      case TourStop.focus:
        return SpotlightStep(
          target: t.find(TourTargetId.focus),
          awaitTarget: true,
          body:
              'Start focus runs a timer with breaks. When you finish, the time '
              'you focused is logged and the block is marked done.',
          nextLabel: last ? 'Got it' : 'Next',
        );
      case TourStop.skip:
        return SpotlightStep(
          target: t.find(TourTargetId.skipBlock),
          awaitTarget: true,
          body:
              "Skip moves this work to a later day. You can undo it from "
              "today's list.",
          nextLabel: last ? 'Got it' : 'Next',
        );
      case TourStop.done:
        return SpotlightStep(
          target: t.find(TourTargetId.doneBlock),
          awaitTarget: true,
          body:
              'Done is for study away from the timer. It asks how long it '
              'really took.',
          nextLabel: last ? 'Got it' : 'Next',
        );
      case TourStop.laterBlocks:
        return SpotlightStep(
          target: t.find(TourTargetId.laterBlocks),
          awaitTarget: true,
          body: 'Tap any later block for the same three: Focus, Done and Skip.',
          nextLabel: last ? 'Got it' : 'Next',
        );
    }
  }
}

class _FinishButton extends StatelessWidget {
  const _FinishButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        key: const ValueKey('tour-add-subject'),
        onPressed: onPressed,
        icon: const Icon(Icons.add),
        label: const Text('Add your first subject'),
      ),
    );
  }
}

/// A small drawing of something the app does not have yet, in the app's own
/// dark colours, marked as an example so nobody tries to tap it.
class _Example extends StatelessWidget {
  const _Example({required this.children});

  final List<Widget> children;

  static const ground = Color(0xFF101216);
  static const card = Color(0xFF171A20);
  static const line = Color(0xFF2A2F38);
  static const ink = Color(0xFFE8EAEF);
  static const muted = Color(0xFF8E95A3);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: ground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(2, 0, 0, 6),
            child: Text(
              'EXAMPLE',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: muted,
              ),
            ),
          ),
          for (final (i, c) in children.indexed) ...[
            if (i > 0) const SizedBox(height: 5),
            c,
          ],
        ],
      ),
    );
  }

  static Widget row(String title, String meta, {bool dot = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: card,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          if (dot) ...[
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFF8C93F2),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                Text(
                  meta,
                  style: const TextStyle(fontSize: 10.5, color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExampleSubject extends StatelessWidget {
  const _ExampleSubject();

  @override
  Widget build(BuildContext context) => _Example(
    children: [
      _Example.row('Chemistry', 'exam 13 Oct · needs 19m a day', dot: true),
    ],
  );
}

class _ExampleTopics extends StatelessWidget {
  const _ExampleTopics();

  @override
  Widget build(BuildContext context) => _Example(
    children: [
      _Example.row('Chapter 4: Aldehydes', '32 pages ≈ 1h 36m'),
      _Example.row('Chapter 5: Amines', '24 pages ≈ 1h 12m'),
    ],
  );
}

class _ExampleBlock extends StatelessWidget {
  const _ExampleBlock();

  @override
  Widget build(BuildContext context) => _Example(
    children: [
      Container(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
        decoration: BoxDecoration(
          color: _Example.card,
          border: Border.all(color: _Example.line),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'NOW · 10:18–11:08',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: Color(0xFFF3A968),
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Chapter 4: Aldehydes',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _Example.ink,
              ),
            ),
            Text(
              'Chemistry · 50m',
              style: TextStyle(fontSize: 10.5, color: _Example.muted),
            ),
            SizedBox(height: 7),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: Color(0xFFF0A055),
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    child: Text(
                      '▶ Start focus',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2A1A0E),
                      ),
                    ),
                  ),
                ),
                Text(
                  'Skip',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFFD5D8DF)),
                ),
                Text(
                  'Done',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFFD5D8DF)),
                ),
              ],
            ),
          ],
        ),
      ),
    ],
  );
}

/// The reminders stop: each thing Android needs allowed, with its own button.
///
/// Nothing here is required to carry on. Next asks for notifications if that
/// row was never used, since without them nothing else on the card matters.
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
          done: state.notificationsAllowed && state.exactAlarmsAllowed,
          title: 'Notifications',
          detail: 'Android may ask twice.',
          action: 'Allow',
          onPressed: state.requestReminderPermissions,
        ),
        _SetupRow(
          key: const ValueKey('tour-allow-background'),
          done: state.batteryExempt,
          title: 'Run in the background',
          detail: 'So reminders are not frozen.',
          action: 'Allow',
          onPressed: state.requestBatteryExemption,
        ),
        // Only on phones that have such a screen. Stock Android has none.
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
              ? 'Arrives in a minute.'
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
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 18,
            color: done ? theme.colorScheme.primary : theme.colorScheme.outline,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  detail,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
