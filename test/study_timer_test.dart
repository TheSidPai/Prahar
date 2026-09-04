import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/domain/study_timer.dart';

/// The timer is derived from elapsed time rather than from a tick counter, and
/// these tests are what make that claim checkable: every one of them jumps the
/// clock forward the way a sleeping phone does, without a single tick firing.
void main() {
  const pomodoro = TimerMode.pomodoro; // 25 / 5
  final start = DateTime(2026, 9, 4, 18, 0);

  group('phases', () {
    test('opens in a work phase with the full interval left', () {
      final s = snapshotOf(pomodoro, Duration.zero);
      expect(s.phase, TimerPhase.work);
      expect(s.secondsLeft, 25 * 60);
      expect(s.focusedSeconds, 0);
      expect(s.completedIntervals, 0);
    });

    test('crosses into rest exactly at the end of the work interval', () {
      final working = snapshotOf(pomodoro, const Duration(minutes: 24, seconds: 59));
      expect(working.phase, TimerPhase.work);
      expect(working.secondsLeft, 1);

      final resting = snapshotOf(pomodoro, const Duration(minutes: 25));
      expect(resting.phase, TimerPhase.rest);
      expect(resting.secondsLeft, 5 * 60);
      expect(resting.completedIntervals, 1);
    });

    test('starts the next work interval after the break', () {
      final s = snapshotOf(pomodoro, const Duration(minutes: 30));
      expect(s.phase, TimerPhase.work);
      expect(s.secondsLeft, 25 * 60);
      expect(s.completedIntervals, 1);
    });
  });

  group('focused time', () {
    test('counts work only, never the break', () {
      // 25 on, then 5 off: the break adds nothing.
      expect(snapshotOf(pomodoro, const Duration(minutes: 25)).focusedMinutes, 25);
      expect(snapshotOf(pomodoro, const Duration(minutes: 30)).focusedMinutes, 25);
    });

    test('accumulates across cycles', () {
      // Two full cycles plus ten minutes of the third work interval.
      final s = snapshotOf(pomodoro, const Duration(minutes: 70));
      expect(s.focusedMinutes, 60);
      expect(s.phase, TimerPhase.work);
    });

    test('counts a part-finished interval', () {
      expect(snapshotOf(pomodoro, const Duration(minutes: 7)).focusedMinutes, 7);
    });
  });

  group('a run through wall-clock time', () {
    test('gains the minutes the phone spent asleep', () {
      // The failure a tick counter has: no timer fires while the process is
      // frozen, so a counting implementation would report zero here.
      final run = TimerRun(mode: pomodoro, startedAt: start);
      final later = start.add(const Duration(minutes: 18));
      expect(run.snapshotAt(later).focusedMinutes, 18);
    });

    test('a pause freezes the clock', () {
      final run = TimerRun(mode: pomodoro, startedAt: start)
          .pause(start.add(const Duration(minutes: 10)));

      // Half an hour of real time passes, all of it paused.
      final later = start.add(const Duration(minutes: 40));
      expect(run.snapshotAt(later).focusedMinutes, 10);
      expect(run.isPaused, isTrue);
      expect(run.phaseEndsAt(later), isNull);
    });

    test('resuming picks up where it stopped', () {
      final paused = TimerRun(mode: pomodoro, startedAt: start)
          .pause(start.add(const Duration(minutes: 10)));
      final resumed = paused.resume(start.add(const Duration(minutes: 40)));

      // Ten minutes of work happened, then thirty minutes of nothing.
      expect(resumed.snapshotAt(start.add(const Duration(minutes: 40)))
          .focusedMinutes, 10);
      // Five more minutes of real time is five more minutes of work.
      expect(resumed.snapshotAt(start.add(const Duration(minutes: 45)))
          .focusedMinutes, 15);
      expect(resumed.isPaused, isFalse);
    });

    test('pausing twice does not double-count the pause', () {
      final run = TimerRun(mode: pomodoro, startedAt: start)
          .pause(start.add(const Duration(minutes: 5)))
          .pause(start.add(const Duration(minutes: 9)));
      expect(run.snapshotAt(start.add(const Duration(minutes: 20)))
          .focusedMinutes, 5);
    });

    test('the next phase boundary is a wall-clock instant', () {
      final run = TimerRun(mode: pomodoro, startedAt: start);
      final now = start.add(const Duration(minutes: 20));
      expect(run.phaseEndsAt(now), start.add(const Duration(minutes: 25)));
    });

    test('a clock that jumps backwards cannot produce negative time', () {
      final run = TimerRun(mode: pomodoro, startedAt: start);
      expect(run.snapshotAt(start.subtract(const Duration(minutes: 5)))
          .focusedSeconds, 0);
    });
  });

  test('deep mode is a longer sitting with a longer break', () {
    const deep = TimerMode.deep;
    expect(snapshotOf(deep, const Duration(minutes: 49)).phase, TimerPhase.work);
    expect(snapshotOf(deep, const Duration(minutes: 50)).phase, TimerPhase.rest);
    expect(snapshotOf(deep, const Duration(minutes: 60)).phase, TimerPhase.work);
    expect(snapshotOf(deep, const Duration(minutes: 60)).focusedMinutes, 50);
  });
}
