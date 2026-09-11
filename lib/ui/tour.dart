import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../domain/tour.dart';
import '../state/app_state.dart';
import 'spotlight.dart';

/// The things the first-run tour points at.
enum TourTargetId {
  navigation,
  subjectsTab,
  addSubject,
  firstSubject,
  addTopic,
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
          body: 'These five tabs are the whole app. Start with Subjects.',
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
    }

    // A stop that waits for a tap has nothing to show without the thing to
    // tap. That is what happens while a sheet is open over it: the tour steps
    // aside, and comes back when the sheet closes, saved or not.
    if (!step.isRead && target == null) return null;

    return Positioned.fill(
      child: SpotlightOverlay(
        // A fresh overlay per stop, so each one fades in rather than the
        // window jumping from one target to the next.
        key: ValueKey((step, target)),
        step: spot,
        onNext: step.isRead ? () => state.tourNext(step) : null,
        onSkip: state.skipTour,
      ),
    );
  }
}
