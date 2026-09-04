/// The study timer's arithmetic, with no Flutter and no clock of its own.
///
/// Everything here is a pure function of *elapsed time*, never of a tick
/// counter. That is the whole design: `Timer.periodic` stops firing when
/// Android freezes the process, so a timer that counts its own ticks quietly
/// loses every minute the phone spent asleep — and this app exists to be
/// honest about how long things actually took. The screen ticks once a second
/// only to repaint; what it paints is recomputed from two timestamps.
library;

/// A work/rest pattern.
///
/// Two, not a slider. The choice a student makes is "short bursts or a long
/// sitting", and offering 3 to 90 minutes in one-minute steps turns a decision
/// into a configuration screen.
class TimerMode {
  /// Stable key for storage. A plain class rather than an enum because a mode
  /// is a pair of durations, and an enum would need a parallel lookup table
  /// that could fall out of step with it.
  final String name;

  final String label;
  final String flavour;
  final int workMinutes;
  final int restMinutes;

  const TimerMode({
    required this.name,
    required this.label,
    required this.flavour,
    required this.workMinutes,
    required this.restMinutes,
  });

  static const pomodoro = TimerMode(
    name: 'pomodoro',
    label: 'Pomodoro',
    flavour: '25 on, 5 off',
    workMinutes: 25,
    restMinutes: 5,
  );

  static const deep = TimerMode(
    name: 'deep',
    label: 'Deep',
    flavour: '50 on, 10 off',
    workMinutes: 50,
    restMinutes: 10,
  );

  static const all = [pomodoro, deep];

  /// Tolerant of anything unrecognised, like every other stored preference:
  /// a value the app cannot read falls back to a working default rather than
  /// preventing it starting.
  static TimerMode byName(String? name) =>
      all.firstWhere((m) => m.name == name, orElse: () => pomodoro);

  int get cycleSeconds => (workMinutes + restMinutes) * 60;
  int get workSeconds => workMinutes * 60;
}

enum TimerPhase { work, rest }

/// What the timer is showing at a given moment.
class TimerSnapshot {
  final TimerPhase phase;

  /// Seconds until this phase ends.
  final int secondsLeft;

  /// Time spent in work phases so far, which is the only number that gets
  /// logged. Break time is not study time.
  final int focusedSeconds;

  /// How many work intervals have been completed in full.
  final int completedIntervals;

  const TimerSnapshot({
    required this.phase,
    required this.secondsLeft,
    required this.focusedSeconds,
    required this.completedIntervals,
  });

  int get focusedMinutes => focusedSeconds ~/ 60;

  bool get isWorking => phase == TimerPhase.work;
}

/// The state of a [mode] timer after [elapsed] of running time.
///
/// [elapsed] must already exclude any time spent paused — see
/// `TimerRun.elapsedAt`.
TimerSnapshot snapshotOf(TimerMode mode, Duration elapsed) {
  final seconds = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
  final cycles = seconds ~/ mode.cycleSeconds;
  final inCycle = seconds % mode.cycleSeconds;
  final working = inCycle < mode.workSeconds;

  final focused = cycles * mode.workSeconds +
      (working ? inCycle : mode.workSeconds);

  return TimerSnapshot(
    phase: working ? TimerPhase.work : TimerPhase.rest,
    secondsLeft: working
        ? mode.workSeconds - inCycle
        : mode.cycleSeconds - inCycle,
    focusedSeconds: focused,
    completedIntervals: cycles + (working ? 0 : 1),
  );
}

/// A timer that has been started, and possibly paused.
///
/// Pausing is stored as accumulated paused time rather than by mutating the
/// start instant, so the two timestamps remain a faithful record of what
/// happened rather than a running total that can drift.
class TimerRun {
  final TimerMode mode;
  final DateTime startedAt;

  /// Total time spent paused before [pausedAt] (or before now, if running).
  final Duration accumulatedPause;

  /// When the current pause began. Null while running.
  final DateTime? pausedAt;

  const TimerRun({
    required this.mode,
    required this.startedAt,
    this.accumulatedPause = Duration.zero,
    this.pausedAt,
  });

  bool get isPaused => pausedAt != null;

  Duration elapsedAt(DateTime now) {
    final frozenAt = pausedAt ?? now;
    final raw = frozenAt.difference(startedAt) - accumulatedPause;
    return raw.isNegative ? Duration.zero : raw;
  }

  TimerSnapshot snapshotAt(DateTime now) => snapshotOf(mode, elapsedAt(now));

  /// When the current phase will end in wall-clock terms, so the boundary can
  /// be handed to the OS as an alarm. Null while paused: a paused timer has no
  /// next boundary, and scheduling one would fire during a break the student
  /// deliberately extended.
  DateTime? phaseEndsAt(DateTime now) {
    if (isPaused) return null;
    return now.add(Duration(seconds: snapshotAt(now).secondsLeft));
  }

  TimerRun pause(DateTime now) =>
      isPaused ? this : TimerRun(
            mode: mode,
            startedAt: startedAt,
            accumulatedPause: accumulatedPause,
            pausedAt: now,
          );

  TimerRun resume(DateTime now) => !isPaused
      ? this
      : TimerRun(
          mode: mode,
          startedAt: startedAt,
          accumulatedPause: accumulatedPause + now.difference(pausedAt!),
        );
}
