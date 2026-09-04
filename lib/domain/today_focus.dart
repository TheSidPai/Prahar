/// Which single block Today should be *about*.
///
/// Pure, and separate from the screen, because "what am I meant to be doing
/// right now" has more edge cases than it first appears — a block already
/// under way, a gap between two, a day that has finished, a day with nothing
/// in it, and a plan the app has been left open past. Deciding that inside a
/// build method means discovering the cases one bug report at a time.
library;

import 'schedule.dart';

enum FocusKind {
  /// The clock is inside this block.
  now,

  /// Nothing is running; this one is next.
  next,

  /// Every block has been dealt with.
  allDone,

  /// There was nothing to do in the first place.
  nothingPlanned,
}

class TodayFocus {
  final FocusKind kind;

  /// The block in question. Null for [FocusKind.allDone] and
  /// [FocusKind.nothingPlanned].
  final StudySession? session;

  /// Minutes until it starts. Zero when it is already running, and zero for a
  /// block whose start has passed without being logged.
  final int minutesUntilStart;

  /// Minutes remaining in the block, when one is running.
  final int minutesLeft;

  const TodayFocus({
    required this.kind,
    this.session,
    this.minutesUntilStart = 0,
    this.minutesLeft = 0,
  });

  bool get hasBlock => session != null;
}

/// Picks the block Today leads with.
///
/// [remaining] is what is still to be done today — the plan already excludes
/// anything logged, because the planner regenerates from remaining work. So
/// an empty list plus something in the log means the day is finished, whereas
/// an empty list and an empty log means the day was always empty. The two
/// deserve different words, which is why [anythingLogged] is asked for.
TodayFocus focusFor({
  required List<StudySession> remaining,
  required bool anythingLogged,
  required int nowMinuteOfDay,
}) {
  if (remaining.isEmpty) {
    return TodayFocus(
      kind: anythingLogged ? FocusKind.allDone : FocusKind.nothingPlanned,
    );
  }

  final ordered = [...remaining]
    ..sort((a, b) => a.startMinuteOfDay.compareTo(b.startMinuteOfDay));

  for (final s in ordered) {
    final start = s.startMinuteOfDay;
    final end = start + s.durationMinutes;
    if (nowMinuteOfDay >= start && nowMinuteOfDay < end) {
      return TodayFocus(
        kind: FocusKind.now,
        session: s,
        minutesLeft: end - nowMinuteOfDay,
      );
    }
  }

  for (final s in ordered) {
    if (s.startMinuteOfDay > nowMinuteOfDay) {
      return TodayFocus(
        kind: FocusKind.next,
        session: s,
        minutesUntilStart: s.startMinuteOfDay - nowMinuteOfDay,
      );
    }
  }

  // Every block has started and none is running: the app was left open
  // through them, or the day rolled over without a replan. The earliest is
  // still the thing to do, and it is due now rather than at a past time.
  return TodayFocus(kind: FocusKind.next, session: ordered.first);
}
