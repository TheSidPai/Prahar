/// Pure domain types.
///
/// Nothing in `lib/domain` or `lib/planner` may import Flutter, touch the
/// database, or perform I/O. That rule is what keeps the planner testable
/// without a device, an emulator, or a running app.
library;

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
  });

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
      );
}

/// A course with a deadline. Deadlines drive urgency; weight lets a student
/// say "this paper is worth more than that one".
class Subject {
  final String id;
  final String name;

  /// Null means "no deadline" — the planner treats it as low urgency rather
  /// than refusing to schedule it.
  final DateTime? examDate;

  /// 1 (minor) .. 5 (critical).
  final int weight;

  /// ARGB, stored as an int so the domain layer stays Flutter-free.
  final int colorValue;

  const Subject({
    required this.id,
    required this.name,
    this.examDate,
    this.weight = 3,
    this.colorValue = 0xFF4F46E5,
  });

  Subject copyWith({
    String? name,
    DateTime? examDate,
    int? weight,
    int? colorValue,
  }) =>
      Subject(
        id: id,
        name: name ?? this.name,
        examDate: examDate ?? this.examDate,
        weight: weight ?? this.weight,
        colorValue: colorValue ?? this.colorValue,
      );
}
