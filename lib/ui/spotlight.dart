import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'brand.dart';
import 'theme.dart';

/// How a spotlight step moves on.
enum SpotlightAdvance {
  /// The note has a Next button, and the highlighted target is shown but
  /// can't be touched. Looking at something must never set it off.
  next,

  /// The highlighted target is the only touchable part of the screen, and
  /// whatever owns the step decides when it has been done. The tour itself
  /// no longer uses this: every stop moves on by Next.
  action,
}

/// A small second note, pointing at a target of its own.
///
/// For a stop about two things at once, like Plan and Progress: one window
/// frames both targets, the main note says what they are for, and a small note
/// for each sits beside the other with its own arrow down to its own target.
@immutable
class SpotlightCompanion {
  const SpotlightCompanion({
    required this.target,
    required this.icon,
    required this.title,
    required this.body,
  });

  final GlobalKey? target;
  final IconData icon;
  final String title;
  final String body;
}

/// One stop on a tour.
@immutable
class SpotlightStep {
  const SpotlightStep({
    required this.body,
    this.title,
    this.target,
    this.companions = const [],
    this.awaitTarget = false,
    this.advance = SpotlightAdvance.next,
    this.nextLabel = 'Next',
    this.quietNext = false,
    this.showMark = false,
    this.extra,
  });

  /// The widget to highlight, found through the GlobalKey placed on it.
  ///
  /// Null, with no companions, centres the note with nothing cut out, which is
  /// the welcome card's shape. A key that isn't on screen gets the same centred
  /// note rather than an error, unless [awaitTarget] says to wait for it.
  final GlobalKey? target;

  /// Small notes, each pointing at its own target. The window grows to frame
  /// every companion's target as well as [target].
  final List<SpotlightCompanion> companions;

  /// Holds the window where it is while the target is missing, instead of
  /// falling back to a centred note.
  ///
  /// For a stop whose target is about to appear: the tour switches tabs as it
  /// goes, and for a frame or two the next stop's target is not built yet. A
  /// note jumping to the middle of the screen and back reads as a glitch.
  final bool awaitTarget;

  final String? title;
  final String body;
  final SpotlightAdvance advance;
  final String nextLabel;

  /// Draws Next as a quiet text button instead of a filled one, for a stop
  /// whose real choice is a button of its own inside [extra].
  final bool quietNext;

  /// Draws the brand mark above the title, for the welcome card.
  final bool showMark;

  /// Anything more the stop needs under its words: a drawing, a checklist, a
  /// button. It scrolls with the words; the note's own buttons stay pinned.
  final Widget? extra;
}

/// A dimmed layer over the whole app, a window onto what a stop is about, a
/// paper note explaining it, and an arrow from one to the other.
///
/// It sits as the top child of a Stack above the app. It only draws and
/// decides where taps go; which stop is showing belongs to whatever places it,
/// which tells it through [stepIndex].
///
/// What keeps it feeling like one guide rather than a series of pop-ups:
///
///  * **It moves between stops.** Given a new [stepIndex], the window slides
///    and reshapes to the new target, the note glides with it, and the arrow
///    draws itself once both have settled. A target that merely moved, on a
///    scroll or a rotation, is followed at once instead, because a window
///    lagging behind what it frames looks broken.
///  * **The note never covers its target.** It goes above or below, whichever
///    has more room, or beside a target too tall for either, like the rail.
///  * **The arrow points at the whole target.** It leaves the side of the note
///    facing the target and lands on the middle of the target's facing edge,
///    square to it.
///  * **It never runs a frame loop of its own.** Measuring happens after
///    frames that are drawn anyway, so a still screen costs nothing.
class SpotlightOverlay extends StatefulWidget {
  const SpotlightOverlay({
    super.key,
    required this.step,
    required this.onSkip,
    this.onNext,
    this.onBack,
    this.stepIndex = 0,
    this.stepCount = 1,
    this.skipLabel = 'Skip',
  });

  final SpotlightStep step;
  final VoidCallback onSkip;

  /// Called by the Next button. Ignored on action steps, which have none.
  final VoidCallback? onNext;

  /// Called by the Back button, which only shows when this is given.
  final VoidCallback? onBack;

  /// Which stop this is. A change here is what makes the window move rather
  /// than jump.
  final int stepIndex;
  final int stepCount;

  final String skipLabel;

  /// Room left around the target inside the window.
  static const holePadding = 8.0;
  static const holeRadius = 18.0;

  /// Distance from the screen's edges, inside the safe area.
  static const margin = 16.0;

  /// Space between the window and the note, which the arrow runs across.
  static const arrowGap = 56.0;

  static const maxBubbleWidth = 360.0;

  /// Less room than this above and below a target, and the note goes beside
  /// it instead.
  static const minBubbleHeight = 160.0;

  static const moveDuration = Duration(milliseconds: 420);

  /// The arrow drawing on, then nudging twice toward its target, then still.
  static const drawDuration = Duration(milliseconds: 2800);

  @override
  State<SpotlightOverlay> createState() => _SpotlightOverlayState();
}

class _SpotlightOverlayState extends State<SpotlightOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _move = AnimationController(
    vsync: this,
    duration: SpotlightOverlay.moveDuration,
    value: 1,
  );
  late final AnimationController _draw = AnimationController(
    vsync: this,
    duration: SpotlightOverlay.drawDuration,
  );

  final _bubbleKey = GlobalKey();
  final _noteKeys = <GlobalKey>[];

  /// The window slides from [_from] to [_to].
  Rect? _from;
  Rect? _to;

  List<Rect?> _noteTargets = const [];
  Rect? _bubble;
  List<Rect?> _notes = const [];

  /// Set when the stop changes, so the next new window is slid to rather than
  /// jumped to.
  bool _stepChanged = false;

  /// Set whenever the arrows need drawing again, once everything has settled.
  bool _drawPending = true;
  bool _arrowsVisible = false;

  @override
  void initState() {
    super.initState();
    _syncNoteKeys();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  void didUpdateWidget(SpotlightOverlay old) {
    super.didUpdateWidget(old);
    _syncNoteKeys();
    if (old.stepIndex != widget.stepIndex ||
        old.step.body != widget.step.body) {
      _stepChanged = true;
      _drawPending = true;
      _arrowsVisible = false;
    }
  }

  @override
  void dispose() {
    _move.dispose();
    _draw.dispose();
    super.dispose();
  }

  void _syncNoteKeys() {
    final count = widget.step.companions.length;
    while (_noteKeys.length < count) {
      _noteKeys.add(GlobalKey());
    }
    if (_noteKeys.length > count) {
      _noteKeys.removeRange(count, _noteKeys.length);
    }
  }

  bool get _still => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  Rect? _shownWindow() {
    final to = _to;
    if (to == null) return null;
    final from = _from;
    if (from == null) return to;
    return Rect.lerp(from, to, Curves.easeInOutCubic.transform(_move.value));
  }

  Rect? _rectOf(GlobalKey? key, RenderBox self, [double inflate = 0]) {
    final box = key?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final topLeft = self.globalToLocal(box.localToGlobal(Offset.zero));
    return (topLeft & box.size).inflate(inflate);
  }

  /// Finds the targets and the notes and, after the next frame, looks again.
  ///
  /// A post-frame callback never schedules a frame by itself, so this chain
  /// only turns over while something else is drawing: a slide, the arrow, a
  /// scroll, a rotation. When the screen is still, it waits.
  void _measure() {
    if (!mounted) return;
    final self = context.findRenderObject();
    if (self is RenderBox && self.hasSize) {
      final step = widget.step;
      final noteTargets = [
        for (final c in step.companions) _rectOf(c.target, self, 6),
      ];

      Rect? window = _rectOf(step.target, self, SpotlightOverlay.holePadding);
      for (final r in noteTargets) {
        if (r != null) window = window == null ? r : window.expandToInclude(r);
      }
      // Kept inside the screen, so a window around something at its edge,
      // like the nav bar, shows its whole ring instead of one side of it.
      if (window != null) {
        window = window.intersect((Offset.zero & self.size).deflate(6));
        if (window.width <= 0 || window.height <= 0) window = null;
      }

      final to = window ?? (step.awaitTarget ? _to : null);
      var changed = false;
      if (to != _to) {
        final shown = _shownWindow();
        final slide = _stepChanged && shown != null && to != null && !_still;
        _from = slide ? shown : to;
        _to = to;
        if (slide) {
          _move.forward(from: 0);
        } else {
          _move.value = 1;
        }
        _stepChanged = false;
        _drawPending = true;
        _arrowsVisible = false;
        changed = true;
      } else if (window != null || !step.awaitTarget) {
        // The new stop's window turned out to be the one already showing.
        _stepChanged = false;
      }

      final bubble = _rectOf(_bubbleKey, self);
      final notes = [for (final k in _noteKeys) _rectOf(k, self)];
      if (bubble != _bubble ||
          !listEquals(notes, _notes) ||
          !listEquals(noteTargets, _noteTargets)) {
        _bubble = bubble;
        _notes = notes;
        _noteTargets = noteTargets;
        changed = true;
      }

      if (_drawPending && !_move.isAnimating && _bubble != null) {
        _drawPending = false;
        _arrowsVisible = true;
        if (_still) {
          _draw.value = 1;
        } else {
          _draw.forward(from: 0);
        }
        changed = true;
      }

      if (changed) setState(() {});
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  List<SpotlightArrow> _arrows() {
    final window = _to;
    if (window == null || !_arrowsVisible) return const [];
    final step = widget.step;
    if (step.companions.isEmpty) {
      final bubble = _bubble;
      if (bubble == null) return const [];
      final arrow = SpotlightArrow.between(bubble, window);
      return arrow == null ? const [] : [arrow];
    }
    return [
      for (var i = 0; i < _notes.length && i < _noteTargets.length; i++)
        if (_notes[i] != null && _noteTargets[i] != null)
          ?SpotlightArrow.between(
            _notes[i]!,
            // Lands on the window's edge, above this note's own target.
            Rect.fromLTRB(
              _noteTargets[i]!.left,
              window.top,
              _noteTargets[i]!.right,
              window.bottom,
            ),
          ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final step = widget.step;

    // Black at different strengths per theme: the dark theme is already
    // nearly black, so a light scrim over it barely reads as dimmed.
    final scrim = Colors.black.withValues(
      alpha: theme.brightness == Brightness.dark ? 0.72 : 0.6,
    );

    final bubble = KeyedSubtree(
      key: _bubbleKey,
      child: _Note(
        key: const ValueKey('spotlight-bubble'),
        step: step,
        stepIndex: widget.stepIndex,
        stepCount: widget.stepCount,
        onNext: widget.onNext,
        onBack: widget.onBack,
        onSkip: widget.onSkip,
        skipLabel: widget.skipLabel,
      ),
    );

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 220),
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: AnimatedBuilder(
        animation: Listenable.merge([_move, _draw]),
        builder: (context, _) => LayoutBuilder(
          builder: (context, box) {
            final size = box.biggest;
            final hole = _shownWindow();

            Widget group(bool notesFirst) {
              final children = <Widget>[
                Flexible(child: bubble),
                if (step.companions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < step.companions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 10),
                        Expanded(
                          child: KeyedSubtree(
                            key: _noteKeys[i],
                            child: _SideNote(
                              key: ValueKey('spotlight-note-$i'),
                              companion: step.companions[i],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ];
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: notesFirst ? children.reversed.toList() : children,
              );
            }

            return Stack(
              children: [
                Positioned.fill(
                  child: _PassThroughHole(
                    hole: step.advance == SpotlightAdvance.action ? _to : null,
                    // Opaque and empty: a tap anywhere on the scrim is caught
                    // here and goes nowhere.
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {},
                      child: CustomPaint(
                        key: const ValueKey('spotlight-scrim'),
                        painter: SpotlightScrimPainter(
                          hole: hole,
                          scrim: scrim,
                          ring: PraharTheme.tourPaper,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      key: const ValueKey('spotlight-arrows'),
                      painter: SpotlightArrowPainter(
                        arrows: _arrows(),
                        elapsedMs:
                            _draw.value *
                            SpotlightOverlay.drawDuration.inMilliseconds,
                        color: PraharTheme.tourPaper,
                      ),
                    ),
                  ),
                ),
                _place(context, size, hole, group),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _place(
    BuildContext context,
    Size size,
    Rect? hole,
    Widget Function(bool notesFirst) group,
  ) {
    final safe = MediaQuery.paddingOf(context);
    const margin = SpotlightOverlay.margin;
    const gap = SpotlightOverlay.arrowGap;
    final width = math.min(
      SpotlightOverlay.maxBubbleWidth,
      math.max(0.0, size.width - margin * 2),
    );

    if (hole == null) {
      return Positioned.fill(
        child: Center(
          child: SizedBox(
            width: width,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: math.max(
                  0.0,
                  size.height - safe.vertical - margin * 2,
                ),
              ),
              child: group(false),
            ),
          ),
        ),
      );
    }

    final top = safe.top + margin;
    final bottom = size.height - safe.bottom - margin;
    final spaceBelow = bottom - (hole.bottom + gap);
    final spaceAbove = (hole.top - gap) - top;
    final spaceLeft = (hole.left - gap) - (safe.left + margin);
    final spaceRight = (size.width - safe.right - margin) - (hole.right + gap);
    final vertical = math.max(spaceAbove, spaceBelow);
    final sideways = math.max(spaceLeft, spaceRight);

    if (vertical < SpotlightOverlay.minBubbleHeight && sideways > vertical) {
      // A target as tall as the screen, like the navigation rail, leaves no
      // room above or below it, so the note goes beside.
      final right = spaceRight >= spaceLeft;
      final along = bottom - top;
      final y = along <= 0
          ? 0.0
          : ((hole.center.dy - top) / along * 2 - 1).clamp(-1.0, 1.0);
      return Positioned(
        top: top,
        height: math.max(0.0, along),
        left: right ? hole.right + gap : null,
        right: right ? null : size.width - hole.left + gap,
        width: math.min(width, sideways),
        child: Align(alignment: Alignment(0, y), child: group(false)),
      );
    }

    final below = spaceBelow >= spaceAbove;
    // Centred on the target where it can be, pushed back inside the screen
    // where it can't.
    final maxLeft = math.max(margin, size.width - margin - width);
    final left = (hole.center.dx - width / 2).clamp(margin, maxLeft);
    return Positioned(
      left: left,
      width: width,
      top: below ? hole.bottom + gap : null,
      bottom: below ? null : size.height - hole.top + gap,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: math.max(0.0, below ? spaceBelow : spaceAbove),
        ),
        // The small notes sit between the main note and the targets, so
        // their arrows are the short ones.
        child: group(below),
      ),
    );
  }
}

/// The note's colours, handed to everything inside it.
///
/// A theme rather than colours set widget by widget, so whatever a stop puts
/// in the note, a checklist or a button, comes out in ink and indigo on paper
/// instead of the app's own light-on-dark and amber.
ThemeData _paperTheme(ThemeData base) {
  const ink = PraharTheme.accentInk;
  return base.copyWith(
    colorScheme: base.colorScheme.copyWith(
      brightness: Brightness.light,
      surface: PraharTheme.tourPaper,
      onSurface: ink,
      onSurfaceVariant: ink.withValues(alpha: 0.72),
      primary: PraharTheme.tourNext,
      onPrimary: Colors.white,
      outline: ink.withValues(alpha: 0.32),
      outlineVariant: ink.withValues(alpha: 0.12),
    ),
    textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    iconTheme: const IconThemeData(color: ink),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: PraharTheme.tourNext,
        foregroundColor: Colors.white,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: PraharTheme.tourNext),
    ),
  );
}

/// The paper note.
///
/// A surface of its own rather than a card. Cards follow Settings > Cards, and
/// the whole point of the note is to look like nothing else in the app.
class _Note extends StatelessWidget {
  const _Note({
    super.key,
    required this.step,
    required this.stepIndex,
    required this.stepCount,
    required this.onSkip,
    required this.skipLabel,
    this.onNext,
    this.onBack,
  });

  final SpotlightStep step;
  final int stepIndex;
  final int stepCount;
  final VoidCallback onSkip;
  final VoidCallback? onNext;
  final VoidCallback? onBack;
  final String skipLabel;

  static const _ink = PraharTheme.accentInk;

  @override
  Widget build(BuildContext context) {
    final theme = _paperTheme(Theme.of(context));
    final centred = step.showMark;
    final showNext = step.advance == SpotlightAdvance.next && onNext != null;
    final quiet = TextButton.styleFrom(
      foregroundColor: _ink.withValues(alpha: 0.72),
      visualDensity: VisualDensity.compact,
    );

    return Theme(
      data: theme,
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Material(
          color: PraharTheme.tourPaper,
          elevation: 10,
          shadowColor: Colors.black,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: DefaultTextStyle.merge(
            style: const TextStyle(color: _ink),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 6, 0),
                  child: Row(
                    children: [
                      const PraharMark(size: 16, palette: MarkPalette.onLight),
                      const SizedBox(width: 8),
                      if (stepCount > 1)
                        Text(
                          '${stepIndex + 1} of $stepCount'.toUpperCase(),
                          key: const ValueKey('spotlight-step'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                            color: _ink.withValues(alpha: 0.6),
                          ),
                        ),
                      const Spacer(),
                      TextButton(
                        key: const ValueKey('spotlight-skip'),
                        onPressed: onSkip,
                        style: quiet,
                        child: Text(skipLabel),
                      ),
                    ],
                  ),
                ),
                // Only the words scroll. The buttons stay pinned below them:
                // otherwise, at a large font on a small phone, the one way
                // forward is scrolled out of sight inside a note that gives no
                // sign it scrolls.
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 14, 0),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      alignment: Alignment.topCenter,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.topLeft,
                          children: [...previous, ?current],
                        ),
                        child: SizedBox(
                          key: ValueKey(stepIndex),
                          width: double.infinity,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: centred
                                ? CrossAxisAlignment.center
                                : CrossAxisAlignment.start,
                            children: [
                              if (step.showMark) ...[
                                const SizedBox(height: 2),
                                const AnimatedPraharMark(
                                  size: 52,
                                  palette: MarkPalette.onLight,
                                ),
                                const SizedBox(height: 10),
                              ],
                              if (step.title != null) ...[
                                Text(
                                  step.title!,
                                  textAlign: centred
                                      ? TextAlign.center
                                      : TextAlign.start,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                              ],
                              Text(
                                step.body,
                                textAlign: centred
                                    ? TextAlign.center
                                    : TextAlign.start,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  height: 1.45,
                                ),
                              ),
                              if (step.extra != null) ...[
                                const SizedBox(height: 10),
                                step.extra!,
                              ],
                              const SizedBox(height: 4),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 10, 10),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // The dots are the first thing to go when the row is
                      // tight. Measured rather than guessed from the width
                      // alone: Back beside a long label like "Show me around"
                      // at a large font overflowed a row that looked roomy.
                      final scaler = MediaQuery.textScalerOf(context);
                      double labelWidth(String text) {
                        final painter = TextPainter(
                          text: TextSpan(
                            text: text,
                            style: theme.textTheme.labelLarge,
                          ),
                          textDirection: TextDirection.ltr,
                          textScaler: scaler,
                          maxLines: 1,
                        )..layout();
                        return painter.width;
                      }

                      final nextWidth = showNext
                          ? labelWidth(step.nextLabel) + 52
                          : 0.0;
                      final backWidth = onBack != null
                          ? labelWidth('Back') + 52
                          : 8.0;
                      final dotsWidth = stepCount * 9.0 + 16;
                      final roomy =
                          stepCount > 1 &&
                          backWidth + dotsWidth + nextWidth <=
                              constraints.maxWidth;
                      final Widget next = !showNext
                          ? const SizedBox.shrink()
                          : step.quietNext
                          ? TextButton(
                              key: const ValueKey('spotlight-next'),
                              onPressed: onNext,
                              style: quiet,
                              child: Text(step.nextLabel),
                            )
                          : FilledButton(
                              key: const ValueKey('spotlight-next'),
                              onPressed: onNext,
                              child: Text(
                                step.nextLabel,
                                textAlign: TextAlign.center,
                              ),
                            );
                      return Row(
                        children: [
                          if (onBack != null)
                            TextButton.icon(
                              key: const ValueKey('spotlight-back'),
                              onPressed: onBack,
                              style: quiet,
                              icon: const Icon(
                                Icons.chevron_left_rounded,
                                size: 20,
                              ),
                              label: const Text('Back'),
                            )
                          else
                            const SizedBox(width: 8),
                          if (roomy)
                            Expanded(
                              child: Center(
                                child: _Dots(
                                  index: stepIndex,
                                  count: stepCount,
                                ),
                              ),
                            ),
                          if (roomy)
                            next
                          else
                            Expanded(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: next,
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.index, required this.count});

  final int index;
  final int count;

  @override
  Widget build(BuildContext context) {
    const ink = PraharTheme.accentInk;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            width: i == index ? 14 : 5,
            height: 5,
            decoration: BoxDecoration(
              color: i == index ? ink : ink.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
      ],
    );
  }
}

class _SideNote extends StatelessWidget {
  const _SideNote({super.key, required this.companion});

  final SpotlightCompanion companion;

  @override
  Widget build(BuildContext context) {
    const ink = PraharTheme.accentInk;
    final text = Theme.of(context).textTheme;
    return Material(
      color: PraharTheme.tourPaper,
      elevation: 8,
      shadowColor: Colors.black,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(companion.icon, size: 16, color: ink),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    companion.title,
                    style: text.titleSmall?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              companion.body,
              style: text.bodySmall?.copyWith(
                color: ink.withValues(alpha: 0.78),
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One arrow, from a note to what it is about.
@immutable
class SpotlightArrow {
  const SpotlightArrow({
    required this.start,
    required this.end,
    required this.startNormal,
    required this.endNormal,
    required this.away,
  });

  final Offset start;
  final Offset end;

  /// The directions the arrow leaves and arrives in: straight out of the
  /// note's edge, and straight into the target's.
  final Offset startNormal;
  final Offset endNormal;

  /// The note's centre, which the curve bows away from.
  final Offset away;

  /// Space left between the arrow's tip and the window's edge.
  static const tipGap = 12.0;

  /// The arrow from [card] to [target], or null when the two are too close
  /// for an arrow to say anything.
  ///
  /// It leaves from the side of the card that faces the target, and lands on
  /// the middle of the target's facing edge. Landing on the nearest corner
  /// instead is what the first version did, and it read as pointing at the
  /// corner rather than at the thing.
  static SpotlightArrow? between(Rect card, Rect target) {
    final cc = card.center;
    final hc = target.center;
    double along(double v, double lo, double hi) {
      final pad = math.min(30.0, (hi - lo) / 2);
      return v.clamp(lo + pad, hi - pad).toDouble();
    }

    final SpotlightArrow arrow;
    if (target.bottom < card.top) {
      arrow = SpotlightArrow(
        start: Offset(along(hc.dx, card.left, card.right), card.top - 8),
        end: Offset(hc.dx, target.bottom + tipGap),
        startNormal: const Offset(0, -1),
        endNormal: const Offset(0, 1),
        away: cc,
      );
    } else if (target.top > card.bottom) {
      arrow = SpotlightArrow(
        start: Offset(along(hc.dx, card.left, card.right), card.bottom + 8),
        end: Offset(hc.dx, target.top - tipGap),
        startNormal: const Offset(0, 1),
        endNormal: const Offset(0, -1),
        away: cc,
      );
    } else if (hc.dx > cc.dx) {
      arrow = SpotlightArrow(
        start: Offset(card.right + 8, along(hc.dy, card.top, card.bottom)),
        end: Offset(target.left - tipGap, hc.dy),
        startNormal: const Offset(1, 0),
        endNormal: const Offset(-1, 0),
        away: cc,
      );
    } else {
      arrow = SpotlightArrow(
        start: Offset(card.left - 8, along(hc.dy, card.top, card.bottom)),
        end: Offset(target.right + tipGap, hc.dy),
        startNormal: const Offset(-1, 0),
        endNormal: const Offset(1, 0),
        away: cc,
      );
    }
    return (arrow.end - arrow.start).distance < 34 ? null : arrow;
  }

  /// A cubic from [start] to [end] that leaves and arrives square, with a
  /// gentle bow away from the note so it never crosses it.
  Path path() {
    final v = end - start;
    final len = v.distance;
    var n = Offset(-v.dy / len, v.dx / len);
    final mid = start + v / 2;
    if ((mid + n * 30 - away).distance < (mid - n * 30 - away).distance) {
      n = -n;
    }
    final k1 = math.min(len * 0.38, 64.0);
    final k2 = math.min(len * 0.34, 52.0);
    final bow = math.min(len * 0.22, 40.0);
    final c1 = start + startNormal * k1 + n * bow;
    final c2 = end + endNormal * k2;
    return Path()
      ..moveTo(start.dx, start.dy)
      ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);
  }
}

/// Draws the arrows: dashed, drawn on like a pen stroke, the head arriving
/// last, then a nudge toward the target, twice, and stillness.
class SpotlightArrowPainter extends CustomPainter {
  SpotlightArrowPainter({
    required this.arrows,
    required this.elapsedMs,
    required this.color,
  });

  final List<SpotlightArrow> arrows;

  /// Time since the arrows started drawing.
  final double elapsedMs;
  final Color color;

  static const _drawMs = 520.0;
  static const _staggerMs = 180.0;
  static const _headAtMs = 440.0;
  static const _headMs = 240.0;
  static const _nudgeAtMs = 760.0;
  static const _nudgeMs = 900.0;
  static const _dash = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (var i = 0; i < arrows.length; i++) {
      final local = elapsedMs - i * _staggerMs;
      final drawn = Curves.easeOutCubic.transform(
        (local / _drawMs).clamp(0.0, 1.0),
      );
      if (drawn <= 0) continue;

      final metrics = arrows[i].path().computeMetrics().toList();
      if (metrics.isEmpty) continue;
      final metric = metrics.first;
      final length = metric.length;
      final tangent = metric.getTangentForOffset(length);
      if (tangent == null) continue;
      final dir = tangent.vector / tangent.vector.distance;

      final nudgeT = local - _nudgeAtMs;
      final nudge = nudgeT > 0 && nudgeT < _nudgeMs * 2
          ? dir * (math.sin(nudgeT / _nudgeMs * math.pi).abs() * 3.5)
          : Offset.zero;

      canvas.save();
      canvas.translate(nudge.dx, nudge.dy);

      final visible = length * drawn;
      for (var d = 0.0; d < visible; d += _dash * 2) {
        canvas.drawPath(
          metric.extractPath(d, math.min(d + _dash, visible)),
          stroke,
        );
      }

      final headT = ((local - _headAtMs) / _headMs).clamp(0.0, 1.0);
      if (headT > 0) {
        final s = 11 * Curves.easeOutBack.transform(headT);
        final angle = math.atan2(dir.dy, dir.dx);
        final tip = arrows[i].end;
        final head = Path()
          ..moveTo(
            tip.dx - s * math.cos(angle - 0.52),
            tip.dy - s * math.sin(angle - 0.52),
          )
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(
            tip.dx - s * math.cos(angle + 0.52),
            tip.dy - s * math.sin(angle + 0.52),
          );
        canvas.drawPath(head, stroke);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(SpotlightArrowPainter old) =>
      old.elapsedMs != elapsedMs ||
      old.color != color ||
      !listEquals(old.arrows, arrows);
}

/// Lets taps inside [hole] fall through to whatever is underneath.
///
/// Reporting "no hit" inside the window is what hands the tap to the next
/// widget down the Stack, which is the app. Everywhere else the child is hit
/// normally, and the child catches and discards it.
class _PassThroughHole extends SingleChildRenderObjectWidget {
  const _PassThroughHole({required this.hole, super.child});

  final Rect? hole;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPassThroughHole(hole);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPassThroughHole renderObject,
  ) {
    renderObject.hole = hole;
  }
}

class _RenderPassThroughHole extends RenderProxyBox {
  _RenderPassThroughHole(this.hole);

  Rect? hole;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (hole != null && hole!.contains(position)) return false;
    return super.hitTest(result, position: position);
  }
}

/// The dim, with a rounded window cut out of it and a ring around the window.
class SpotlightScrimPainter extends CustomPainter {
  SpotlightScrimPainter({
    required this.hole,
    required this.scrim,
    required this.ring,
  });

  /// Where the window is drawn this frame, part way through a slide or not.
  final Rect? hole;
  final Color scrim;

  /// The paper colour, so the window, the arrow and the note read as one
  /// guide laid over the app.
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Path()..addRect(Offset.zero & size);
    final window = hole;
    if (window == null) {
      canvas.drawPath(screen, Paint()..color = scrim);
      return;
    }

    final radius = math.min(
      SpotlightOverlay.holeRadius,
      window.shortestSide / 2,
    );
    final shape = RRect.fromRectAndRadius(window, Radius.circular(radius));
    canvas.drawPath(
      Path.combine(PathOperation.difference, screen, Path()..addRRect(shape)),
      Paint()..color = scrim,
    );

    // A soft halo first, then a thin, crisp ring on top of it.
    canvas.drawRRect(
      shape.inflate(2),
      Paint()
        ..color = ring.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(SpotlightScrimPainter old) =>
      old.hole != hole || old.scrim != scrim || old.ring != ring;
}
