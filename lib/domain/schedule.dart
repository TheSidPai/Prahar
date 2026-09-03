import 'models.dart';

/// A period the student cannot study: a lecture, lunch, a commute, a shift.
///
/// Scheduling into time the student is occupied does not merely waste that
/// block — it teaches them the schedule is fiction, and a plan that is
/// ignored once tends to be ignored thereafter.
class BusySlot {
  final String id;
  final String label;
  final int startMinute;
  final int endMinute;

  /// `DateTime.monday`..`sunday` for something that repeats weekly.
  /// Null when this is a one-off on [date].
  final int? weekday;

  /// The single day this applies to, when [weekday] is null.
  final DateTime? date;

  const BusySlot({
    required this.id,
    required this.label,
    required this.startMinute,
    required this.endMinute,
    this.weekday,
    this.date,
  });

  bool get repeatsWeekly => weekday != null;

  int get durationMinutes => endMinute - startMinute;

  bool appliesTo(DateTime day) {
    if (weekday != null) return day.weekday == weekday;
    final d = date;
    return d != null && dateKey(d) == dateKey(day);
  }
}

/// How much time the student actually has, per weekday, with per-date
/// overrides for holidays, exam days and unusually free weekends.
class Availability {
  /// `DateTime.monday` (1) .. `DateTime.sunday` (7) -> minutes.
  final Map<int, int> minutesByWeekday;

  /// `yyyy-mm-dd` -> minutes. Wins over the weekday default.
  /// A `0` here is how a holiday or a day off is expressed.
  final Map<String, int> overrides;

  /// Periods blocked out. Subtracted from the study window to give the
  /// intervals a block may actually occupy.
  final List<BusySlot> busy;

  const Availability({
    required this.minutesByWeekday,
    this.overrides = const {},
    this.busy = const [],
  });

  /// The intervals of [day] that are inside the study window and not busy,
  /// as `(start, end)` minute pairs, sorted and non-overlapping.
  ///
  /// Overlapping busy slots are merged first — a student will happily enter
  /// "class 09:00-13:00" and "lab 11:00-12:00" without thinking about it, and
  /// naive subtraction of the second would re-open a gap inside the first.
  List<(int, int)> freeIntervals(
    DateTime day, {
    required int windowStart,
    required int windowEnd,
  }) {
    if (windowEnd <= windowStart) return const [];

    final blocks = busy
        .where((b) => b.appliesTo(day))
        .map((b) => (
              b.startMinute.clamp(windowStart, windowEnd),
              b.endMinute.clamp(windowStart, windowEnd),
            ))
        .where((r) => r.$2 > r.$1)
        .toList()
      ..sort((a, b) => a.$1.compareTo(b.$1));

    final merged = <(int, int)>[];
    for (final b in blocks) {
      if (merged.isNotEmpty && b.$1 <= merged.last.$2) {
        final last = merged.removeLast();
        merged.add((last.$1, last.$2 > b.$2 ? last.$2 : b.$2));
      } else {
        merged.add(b);
      }
    }

    final free = <(int, int)>[];
    var cursor = windowStart;
    for (final b in merged) {
      if (b.$1 > cursor) free.add((cursor, b.$1));
      if (b.$2 > cursor) cursor = b.$2;
    }
    if (cursor < windowEnd) free.add((cursor, windowEnd));
    return free;
  }

  /// Minutes left in the window on [day] once busy slots are removed.
  int freeMinutesOn(
    DateTime day, {
    required int windowStart,
    required int windowEnd,
  }) =>
      freeIntervals(day, windowStart: windowStart, windowEnd: windowEnd)
          .fold(0, (a, r) => a + (r.$2 - r.$1));

  Availability withBusy(List<BusySlot> next) => Availability(
        minutesByWeekday: minutesByWeekday,
        overrides: overrides,
        busy: next,
      );

  /// A sane starting point: 2h on weekdays, 4h on weekends.
  factory Availability.standard() => const Availability(minutesByWeekday: {
        DateTime.monday: 120,
        DateTime.tuesday: 120,
        DateTime.wednesday: 120,
        DateTime.thursday: 120,
        DateTime.friday: 120,
        DateTime.saturday: 240,
        DateTime.sunday: 240,
      });

  int minutesOn(DateTime day) {
    final o = overrides[dateKey(day)];
    if (o != null) return o;
    return minutesByWeekday[day.weekday] ?? 0;
  }

  /// Inclusive of both [from] and [to].
  ///
  /// Steps by calendar date rather than by a 24-hour Duration so a DST
  /// boundary cannot make two iterations land on the same day.
  int totalBetween(DateTime from, DateTime to) {
    final end = dateOnly(to);
    var total = 0;
    for (var d = dateOnly(from);
        !d.isAfter(end);
        d = DateTime(d.year, d.month, d.day + 1)) {
      total += minutesOn(d);
    }
    return total;
  }

  Availability withOverride(DateTime day, int minutes) => Availability(
        minutesByWeekday: minutesByWeekday,
        overrides: {...overrides, dateKey(day): minutes},
        busy: busy,
      );

  Availability withWeekday(int weekday, int minutes) => Availability(
        minutesByWeekday: {...minutesByWeekday, weekday: minutes},
        overrides: overrides,
        busy: busy,
      );
}

enum SessionKind { newMaterial, review }

enum SessionStatus { planned, done, skipped }

/// One block of study on the calendar. Sessions are regenerated on every
/// replan, so anything the student *did* must be recorded on the Topic
/// (as `completedMinutes`), never only here.
class StudySession {
  final String id;
  final String topicId;
  final String subjectId;

  /// Denormalised so notifications and list rows need no joins.
  final String topicTitle;
  final String subjectName;

  final DateTime date;
  final int startMinuteOfDay;
  final int durationMinutes;
  final SessionKind kind;
  final SessionStatus status;

  const StudySession({
    required this.id,
    required this.topicId,
    required this.subjectId,
    required this.topicTitle,
    required this.subjectName,
    required this.date,
    required this.startMinuteOfDay,
    required this.durationMinutes,
    this.kind = SessionKind.newMaterial,
    this.status = SessionStatus.planned,
  });

  DateTime get startsAt =>
      DateTime(date.year, date.month, date.day, 0, startMinuteOfDay);

  DateTime get endsAt =>
      startsAt.add(Duration(minutes: durationMinutes));

  int get endMinuteOfDay => startMinuteOfDay + durationMinutes;

  bool get isReview => kind == SessionKind.review;

  StudySession copyWith({SessionStatus? status}) => StudySession(
        id: id,
        topicId: topicId,
        subjectId: subjectId,
        topicTitle: topicTitle,
        subjectName: subjectName,
        date: date,
        startMinuteOfDay: startMinuteOfDay,
        durationMinutes: durationMinutes,
        kind: kind,
        status: status ?? this.status,
      );
}

/// What actually happened, as opposed to what was planned.
///
/// Unlike [StudySession] this is durable: it is the one thing in the app that
/// cannot be recomputed. Titles are denormalised onto it so a completed block
/// still renders after its topic or subject has been deleted.
class LoggedSession {
  final String id;
  final String topicId;
  final String subjectId;
  final String topicTitle;
  final String subjectName;
  final DateTime day;
  final int plannedMinutes;
  final int actualMinutes;
  final SessionKind kind;
  final SessionStatus status;

  const LoggedSession({
    required this.id,
    required this.topicId,
    required this.subjectId,
    required this.topicTitle,
    required this.subjectName,
    required this.day,
    required this.plannedMinutes,
    required this.actualMinutes,
    required this.kind,
    required this.status,
  });

  bool get wasSkipped => status == SessionStatus.skipped;

  /// Time this entry consumed from the day.
  ///
  /// A skipped block still costs its slot — "skip" means *not today*, so the
  /// planner must not immediately offer the same work again this afternoon.
  int get consumedMinutes => wasSkipped ? plannedMinutes : actualMinutes;
}

/// The honest answer to "can I actually finish this?".
///
/// Surfacing this prominently is the single most valuable thing the app does.
/// A planner that silently generates an impossible schedule is worse than no
/// planner at all.
class Feasibility {
  final int requiredMinutes;
  final int availableMinutes;

  /// Work that did not fit before the horizon.
  final int unscheduledMinutes;

  final List<String> warnings;

  const Feasibility({
    required this.requiredMinutes,
    required this.availableMinutes,
    required this.unscheduledMinutes,
    this.warnings = const [],
  });

  bool get isFeasible => unscheduledMinutes == 0 && warnings.isEmpty;

  bool get fits => unscheduledMinutes == 0;

  /// >1 means more work than time.
  double get loadRatio =>
      availableMinutes == 0 ? double.infinity : requiredMinutes / availableMinutes;

  /// Extra minutes per day needed over [days] to close the gap.
  int extraMinutesPerDay(int days) =>
      days <= 0 ? unscheduledMinutes : (unscheduledMinutes / days).ceil();
}

class Plan {
  final List<StudySession> sessions;
  final Feasibility feasibility;
  final DateTime generatedAt;

  const Plan({
    required this.sessions,
    required this.feasibility,
    required this.generatedAt,
  });

  List<StudySession> onDate(DateTime day) {
    final k = dateKey(day);
    return sessions.where((s) => dateKey(s.date) == k).toList()
      ..sort((a, b) => a.startMinuteOfDay.compareTo(b.startMinuteOfDay));
  }

  int minutesOn(DateTime day) =>
      onDate(day).fold(0, (a, s) => a + s.durationMinutes);

  DateTime? get lastDate => sessions.isEmpty
      ? null
      : sessions.map((s) => s.date).reduce((a, b) => a.isAfter(b) ? a : b);
}
