import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../domain/format.dart';
import '../domain/preferences.dart';
import '../domain/schedule.dart';
import '../domain/study_timer.dart';
import '../state/app_state.dart';
import 'glass.dart';
import 'theme.dart';

/// A focus timer for one study block.
///
/// The point is not the countdown — any clock does that. It is that finishing
/// a session logs the minutes actually spent working, straight into the same
/// `actual_minutes` field the calibration loop reads. Until now that number
/// came from a slider the student dragged after the fact, which is a guess
/// dressed as data; every estimate the app learns was built on it.
///
/// Time is read from the wall clock through [TimerRun], never accumulated by
/// counting ticks: Android freezes the process when the screen goes off, which
/// is exactly when a focus timer should be running. The once-a-second timer
/// here only triggers a repaint.
class TimerScreen extends StatefulWidget {
  const TimerScreen({super.key, required this.session});

  final StudySession session;

  @override
  State<TimerScreen> createState() => _TimerScreenState();
}

class _TimerScreenState extends State<TimerScreen> {
  Timer? _ticker;
  TimerRun? _run;
  late TimerMode _mode;
  TimerPhase? _lastPhase;

  @override
  void initState() {
    super.initState();
    _mode = TimerMode.byName(context.read<AppState>().prefs.timerMode);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // The alert belongs to a timer that no longer exists. Leaving it pending
    // would ring in the middle of something else entirely.
    context.read<AppState>().notifier.cancelTimerAlert();
    _keepAwake(false);
    super.dispose();
  }

  /// Holds the display on while the clock is actually running.
  ///
  /// The countdown itself never needed this — it is derived from the wall
  /// clock, so it survives the screen going off and the process being frozen.
  /// What did not survive was being able to *look* at it: the display slept
  /// mid-session and the phone had to be woken to see how long was left.
  ///
  /// Only while running, and released on pause, on leaving, and on dispose. A
  /// paused timer that holds the screen on is a battery drain with nothing to
  /// show for it, and dispose is the one that matters most: a wakelock that
  /// outlives the screen holding it is a bug the user pays for in percent.
  ///
  /// Failures are swallowed on purpose. There is no plugin behind the channel
  /// in a widget test, and a focus timer is not worth failing a test — or a
  /// session — over.
  void _keepAwake(bool on) {
    unawaited(
      (on ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((_) {}),
    );
  }

  void _start() {
    final now = DateTime.now();
    setState(() {
      _run = TimerRun(mode: _mode, startedAt: now);
      _lastPhase = TimerPhase.work;
    });
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _armAlert();
    _keepAwake(true);

    final state = context.read<AppState>();
    state.updatePrefs(state.prefs.copyWith(timerMode: _mode.name));
  }

  void _tick() {
    final run = _run;
    if (run == null || !mounted) return;
    final phase = run.snapshotAt(DateTime.now()).phase;
    // Re-arm only on a boundary. Rescheduling every second would hammer the
    // alarm manager for no gain.
    if (phase != _lastPhase) {
      _lastPhase = phase;
      _armAlert();
    }
    setState(() {});
  }

  /// Hands the end of the current phase to the OS.
  ///
  /// The screen will be off and face down — that is the point of the exercise —
  /// so the boundary has to survive the process being frozen. Same mechanism
  /// as a study-block reminder, on its own notification id.
  void _armAlert() {
    final run = _run;
    if (run == null) return;
    final notifier = context.read<AppState>().notifier;
    final endsAt = run.phaseEndsAt(DateTime.now());
    if (endsAt == null) {
      notifier.cancelTimerAlert();
      return;
    }

    final working = run.snapshotAt(DateTime.now()).isWorking;
    notifier.scheduleTimerAlert(
      when: endsAt,
      title: working ? 'Break time' : 'Back to it',
      body: working
          ? '${_mode.workMinutes} minutes done. '
                '${_mode.restMinutes} minutes off.'
          : 'Break over — ${widget.session.topicTitle}.',
    );
  }

  void _togglePause() {
    final run = _run;
    if (run == null) return;
    final now = DateTime.now();
    setState(() => _run = run.isPaused ? run.resume(now) : run.pause(now));
    _armAlert();
    _keepAwake(!_run!.isPaused);
  }

  /// Logs the focused minutes against the block and leaves.
  Future<void> _finish() async {
    final run = _run;
    final minutes = run == null
        ? 0
        : run.snapshotAt(DateTime.now()).focusedMinutes;
    final state = context.read<AppState>();

    _ticker?.cancel();
    _keepAwake(false);
    await state.notifier.cancelTimerAlert();
    if (minutes > 0) {
      await state.markDone(widget.session, actualMinutes: minutes);
    }

    if (mounted) Navigator.pop(context, minutes);
  }

  /// Leaving with work on the clock asks first — those minutes are the only
  /// record that the session happened, and a back-swipe should not delete it.
  Future<bool> _confirmDiscard() async {
    final run = _run;
    if (run == null) return true;
    final minutes = run.snapshotAt(DateTime.now()).focusedMinutes;
    if (minutes < 1) return true;

    final choice = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave the timer?'),
        content: Text(
          "You've focused for ${formatMinutes(minutes)}. Log it against "
          '${widget.session.topicTitle}, or throw it away?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'stay'),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'discard'),
            child: const Text('Discard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'log'),
            child: const Text('Log it'),
          ),
        ],
      ),
    );

    if (choice == 'log') {
      await _finish();
      return false; // _finish pops for us
    }
    return choice == 'discard';
  }

  /// Backing out, whether by the close button or a back gesture.
  Future<void> _leave() async {
    if (!await _confirmDiscard()) return;
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final run = _run;
    final now = DateTime.now();
    final snap = run?.snapshotAt(now);
    final glass =
        context.select<AppState, MaterialChoice>(
          (s) => s.prefs.materialChoice,
        ) ==
        MaterialChoice.glass;

    final body = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.session.subjectName.toUpperCase(),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.6,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.session.topicTitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 28),
              _Dial(
                mode: _mode,
                snapshot: snap,
                paused: run?.isPaused ?? false,
                glass: glass,
              ),
              const SizedBox(height: 24),
              if (snap != null)
                Text(
                  '${formatMinutes(snap.focusedMinutes)} focused'
                  ' of ${formatMinutes(widget.session.durationMinutes)} planned',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              const SizedBox(height: 28),
              if (run == null) ..._modePicker(theme) else ..._controls(snap!),
            ],
          ),
        ),
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Focus'),
          leading: IconButton(icon: const Icon(Icons.close), onPressed: _leave),
        ),
        body: body,
      ),
    );
  }

  List<Widget> _modePicker(ThemeData theme) => [
    for (final mode in TimerMode.all)
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: mode.name == _mode.name
                  ? PraharTheme.accent
                  : theme.colorScheme.outlineVariant,
              width: mode.name == _mode.name ? 2 : 1,
            ),
          ),
          child: ListTile(
            title: Text(mode.label),
            subtitle: Text(mode.flavour),
            trailing: mode.name == _mode.name
                ? const Icon(Icons.check_circle, size: 20)
                : null,
            onTap: () => setState(() => _mode = mode),
          ),
        ),
      ),
    const SizedBox(height: 10),
    FilledButton.icon(
      onPressed: _start,
      icon: const Icon(Icons.play_arrow),
      label: const Text('Start'),
    ),
  ];

  List<Widget> _controls(TimerSnapshot snap) => [
    Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _togglePause,
            icon: Icon(_run!.isPaused ? Icons.play_arrow : Icons.pause),
            label: Text(_run!.isPaused ? 'Resume' : 'Pause'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton.icon(
            onPressed: snap.focusedMinutes > 0 ? _finish : null,
            icon: const Icon(Icons.check),
            label: const Text('Log it'),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
          ),
        ),
      ],
    ),
    const SizedBox(height: 10),
    Text(
      snap.completedIntervals == 0
          ? 'Logging stops the timer and records the focused time.'
          : '${snap.completedIntervals} interval'
                '${snap.completedIntervals == 1 ? '' : 's'} done',
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall,
    ),
  ];
}

/// The countdown itself: a ring that empties over the phase, with the clock in
/// the middle. Amber while working, quiet while resting — the same division of
/// labour the rest of the app uses, where amber means effort.
class _Dial extends StatelessWidget {
  const _Dial({
    required this.mode,
    required this.snapshot,
    required this.paused,
    required this.glass,
  });

  final TimerMode mode;
  final TimerSnapshot? snapshot;
  final bool paused;
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snap = snapshot;

    final phaseSeconds = snap == null
        ? mode.workSeconds
        : (snap.isWorking ? mode.workSeconds : mode.restMinutes * 60);
    final left = snap?.secondsLeft ?? mode.workSeconds;
    final progress = phaseSeconds == 0 ? 0.0 : 1 - (left / phaseSeconds);

    final colour = snap == null || snap.isWorking
        ? PraharTheme.accent
        : theme.colorScheme.primary;

    final dial = SizedBox(
      width: 220,
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 220,
            height: 220,
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: 10,
              strokeCap: StrokeCap.round,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: colour,
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _clock(left),
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                snap == null
                    ? mode.flavour
                    : paused
                    ? 'Paused'
                    : (snap.isWorking ? 'Focus' : 'Break'),
                style: theme.textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.4,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (!glass) return Center(child: dial);
    return Center(
      child: GlassSurface(
        borderRadius: BorderRadius.circular(140),
        padding: const EdgeInsets.all(14),
        child: dial,
      ),
    );
  }

  /// `mm:ss`, tabular so the digits do not jitter as they change.
  static String _clock(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
