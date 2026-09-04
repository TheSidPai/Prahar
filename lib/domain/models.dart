/// Pure domain types.
///
/// Nothing in `lib/domain` or `lib/planner` may import Flutter, touch the
/// database, or perform I/O. That rule is what keeps the planner testable
/// without a device, an emulator, or a running app.
library;

import 'format.dart';

/// Strips the time component so dates compare and hash predictably.
///
/// `DateTime` equality includes milliseconds, which makes untruncated dates
/// useless as map keys. Every date in this app is normalised through here.
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Stable `yyyy-mm-dd` key for maps and storage.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

DateTime parseDateKey(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

enum ResourceKind { book, video, pdf, url, problemSet }

/// Something a topic is studied *from*. Doubles as the basis for effort
/// estimation: pages, runtime and problem counts are far easier for a student
/// to supply accurately than "how many minutes will this take".
class Resource {
  final String id;
  final String topicId;
  final ResourceKind kind;
  final String title;

  /// URL, shelf location, file path — free text.
  final String? locator;

  final int? pageStart;
  final int? pageEnd;
  final int? durationSeconds;
  final int? problemCount;

  /// Pages read / seconds watched / problems solved so far.
  final int completedUnits;

  const Resource({
    required this.id,
    required this.topicId,
    required this.kind,
    required this.title,
    this.locator,
    this.pageStart,
    this.pageEnd,
    this.durationSeconds,
    this.problemCount,
    this.completedUnits = 0,
  });

  int? get pages =>
      (pageStart != null && pageEnd != null) ? pageEnd! - pageStart! + 1 : null;

  /// Total units of work this resource represents, in its own unit
  /// (pages, seconds, problems). Null when the resource carries no measure.
  int? get totalUnits => switch (kind) {
        ResourceKind.book || ResourceKind.pdf => pages,
        ResourceKind.video => durationSeconds,
        ResourceKind.problemSet => problemCount,
        ResourceKind.url => null,
      };

  Resource copyWith({int? completedUnits, String? locator, String? title}) =>
      Resource(
        id: id,
        topicId: topicId,
        kind: kind,
        title: title ?? this.title,
        locator: locator ?? this.locator,
        pageStart: pageStart,
        pageEnd: pageEnd,
        durationSeconds: durationSeconds,
        problemCount: problemCount,
        completedUnits: completedUnits ?? this.completedUnits,
      );
}

enum TopicStatus { notStarted, inProgress, done }

/// The unit the student actually typed.
///
/// Stored alongside the derived minutes so a topic can be shown back in the
/// terms it was entered — "200 pages", not "600 minutes" — and, more
/// importantly, so estimates can be recomputed when calibration learns the
/// student's real reading speed. Without the original count there is nothing to
/// recompute from, which is why `session_log` has been collecting timing data
/// that could never be applied.
enum EffortUnit { minutes, pages, problems }

/// The unit the planner schedules. A topic is a leaf of the syllabus with an
/// effort estimate attached.
class Topic {
  final String id;
  final String subjectId;
  final String title;

  /// Total effort. Either entered by hand or derived from resources via
  /// [EffortEstimator].
  final int estimatedMinutes;

  /// Effort already logged against this topic.
  final int completedMinutes;

  /// 1 (easy) .. 5 (hard). Feeds the priority score and, later, review spacing.
  final int difficulty;

  /// Topics that must be finished before this one can be scheduled.
  final List<String> prerequisiteIds;

  final TopicStatus status;

  /// When the topic was first finished — anchors the spaced-repetition ladder.
  final DateTime? firstCompletedOn;

  /// A single link a student can jump to — video, notes, PDF, exercises.
  ///
  /// Deliberately one field rather than a list: the resources table has never
  /// had a UI, and the honest question is "what one link do I need for this
  /// topic", not "let me build a bibliography". Blank when the topic is
  /// self-contained.
  final String? link;

  /// How the estimate was expressed when it was entered.
  final EffortUnit estimateUnit;

  /// The figure the student typed, in [estimateUnit].
  final int estimateAmount;

  /// Minutes per unit used at the time. Recorded rather than re-derived so a
  /// later change to the rate cannot silently rewrite an estimate the student
  /// is halfway through — a progress bar that moves backwards on its own
  /// destroys trust faster than a wrong estimate does.
  final double estimateRate;

  const Topic({
    required this.id,
    required this.subjectId,
    required this.title,
    required this.estimatedMinutes,
    this.completedMinutes = 0,
    this.difficulty = 3,
    this.prerequisiteIds = const [],
    this.status = TopicStatus.notStarted,
    this.firstCompletedOn,
    this.estimateUnit = EffortUnit.minutes,
    int? estimateAmount,
    this.estimateRate = 1.0,
    this.link,
  }) : estimateAmount = estimateAmount ?? estimatedMinutes;

  /// Builds a topic from what the student actually entered.
  ///
  /// [estimatedMinutes] is derived here and then stored, rather than computed
  /// on every read: the planner reads it constantly and must stay free of the
  /// estimator and of per-subject rates.
  factory Topic.fromEstimate({
    required String id,
    required String subjectId,
    required String title,
    required EffortUnit unit,
    required int amount,
    required double rate,
    int completedMinutes = 0,
    int difficulty = 3,
    List<String> prerequisiteIds = const [],
    TopicStatus status = TopicStatus.notStarted,
    DateTime? firstCompletedOn,
  }) =>
      Topic(
        id: id,
        subjectId: subjectId,
        title: title,
        estimatedMinutes: (amount * rate).round().clamp(1, 1 << 30),
        completedMinutes: completedMinutes,
        difficulty: difficulty,
        prerequisiteIds: prerequisiteIds,
        status: status,
        firstCompletedOn: firstCompletedOn,
        estimateUnit: unit,
        estimateAmount: amount,
        estimateRate: rate,
      );

  int get remainingMinutes =>
      (estimatedMinutes - completedMinutes).clamp(0, estimatedMinutes);

  bool get isDone => status == TopicStatus.done || remainingMinutes == 0;

  double get progress =>
      estimatedMinutes == 0 ? 1.0 : completedMinutes / estimatedMinutes;

  Topic copyWith({
    String? title,
    int? estimatedMinutes,
    int? completedMinutes,
    int? difficulty,
    List<String>? prerequisiteIds,
    TopicStatus? status,
    DateTime? firstCompletedOn,
    EffortUnit? estimateUnit,
    int? estimateAmount,
    double? estimateRate,
    String? link,
    bool clearLink = false,
  }) =>
      Topic(
        id: id,
        subjectId: subjectId,
        title: title ?? this.title,
        estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
        completedMinutes: completedMinutes ?? this.completedMinutes,
        difficulty: difficulty ?? this.difficulty,
        prerequisiteIds: prerequisiteIds ?? this.prerequisiteIds,
        status: status ?? this.status,
        firstCompletedOn: firstCompletedOn ?? this.firstCompletedOn,
        estimateUnit: estimateUnit ?? this.estimateUnit,
        estimateAmount: estimateAmount ?? this.estimateAmount,
        estimateRate: estimateRate ?? this.estimateRate,
        link: clearLink ? null : (link ?? this.link),
      );

  /// "200 pages", "45 problems", "1h 30m" — the estimate as it was entered.
  String get estimateLabel => switch (estimateUnit) {
        EffortUnit.pages => '$estimateAmount pages',
        EffortUnit.problems => '$estimateAmount problems',
        EffortUnit.minutes => formatMinutes(estimateAmount),
      };
}

/// A course with a deadline. Deadlines drive urgency; weight lets a student
/// say "this paper is worth more than that one".
class Subject {
  final String id;
  final String name;

  /// Null means "no deadline" — the planner treats it as low urgency rather
  /// than refusing to schedule it. Date only; the time of day, if known, is
  /// [examMinuteOfDay].
  final DateTime? examDate;

  /// What time the exam starts, in minutes from midnight. Null means the time
  /// is unknown, and the exam day counts as a full day of preparation — which
  /// is what every subject did before this field existed.
  ///
  /// Kept separate from [examDate] rather than folded into one timestamp so
  /// that every date comparison in the app — calendar grouping, archive
  /// checks, the planner's day loop — keeps working on a plain date, and so
  /// "I know the day but not the time" stays expressible.
  final int? examMinuteOfDay;

  /// 1 (minor) .. 5 (critical).
  final int weight;

  /// ARGB, stored as an int so the domain layer stays Flutter-free.
  final int colorValue;

  const Subject({
    required this.id,
    required this.name,
    this.examDate,
    this.examMinuteOfDay,
    this.weight = 3,
    this.colorValue = 0xFF4F46E5,
  });

  /// The exam as a single moment, when the time is known.
  DateTime? get examAt {
    final d = examDate;
    if (d == null) return null;
    final m = examMinuteOfDay;
    if (m == null) return d;
    return DateTime(d.year, d.month, d.day, m ~/ 60, m % 60);
  }

  /// How much of the exam day is actually available to study in: all of it
  /// when no time is known, otherwise the share of the study window that
  /// falls before the exam starts.
  ///
  /// A 9am exam against a 06:00–22:00 window leaves 3 of 16 hours, so the
  /// exam day is worth 0.19 of a day rather than a whole one.
  double examDayShare({required int windowStartMinute, required int windowEndMinute}) {
    final m = examMinuteOfDay;
    if (m == null) return 1;
    final span = windowEndMinute - windowStartMinute;
    if (span <= 0) return 0;
    return ((m - windowStartMinute) / span).clamp(0.0, 1.0);
  }

  /// Days of preparation between [from] and the exam.
  ///
  /// Whole days plus the usable share of the exam day itself. Null when there
  /// is no exam date. This is what both the planner's urgency score and the
  /// "needs X a day" figure divide by, so that the two can never disagree
  /// about how much time is left.
  ///
  /// Only the date part of [from] is used: a day already begun still counts
  /// as a day here, which is what "days left" has always meant in this app.
  double? prepDaysFrom(
    DateTime from, {
    required int windowStartMinute,
    required int windowEndMinute,
  }) {
    final exam = examDate;
    if (exam == null) return null;
    final days = dateOnly(exam).difference(dateOnly(from)).inDays;
    if (days < 0) return 0;
    return days +
        examDayShare(
          windowStartMinute: windowStartMinute,
          windowEndMinute: windowEndMinute,
        );
  }

  Subject copyWith({
    String? name,
    DateTime? examDate,
    int? examMinuteOfDay,
    int? weight,
    int? colorValue,
  }) =>
      Subject(
        id: id,
        name: name ?? this.name,
        examDate: examDate ?? this.examDate,
        examMinuteOfDay: examMinuteOfDay ?? this.examMinuteOfDay,
        weight: weight ?? this.weight,
        colorValue: colorValue ?? this.colorValue,
      );
}
