import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../domain/models.dart';
import '../domain/preferences.dart';
import '../domain/schedule.dart';
import '../notifications/notifier.dart';
import '../planner/planner.dart';

String newId() {
  final r = Random();
  return '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${r.nextInt(0x7fffffff).toRadixString(36)}';
}

/// Single source of truth for the UI.
///
/// Every mutation follows the same shape: write to SQLite, regenerate the
/// plan, re-hand the alarms to the OS, notify listeners. Because the planner
/// is pure and fast, replanning on every edit costs nothing and removes any
/// chance of the schedule going stale.
class AppState extends ChangeNotifier {
  AppState({required this.db, required this.notifier});

  final PraharDatabase db;
  final Notifier notifier;

  List<Subject> subjects = const [];
  List<Topic> topics = const [];
  Availability availability = Availability.standard();
  Prefs prefs = const Prefs();
  Plan? plan;

  /// Rebuilt whenever [prefs] changes, so the study window is honoured.
  Planner get planner => Planner(config: prefs.toConfig());

  /// What has already been logged today — done or skipped.
  List<LoggedSession> todayLog = const [];

  int streak = 0;
  bool loading = true;
  bool exactAlarmsAllowed = true;

  /// False means reminders will not arrive until the app is opened by hand.
  /// Surfaced loudly, because everything else about the app is pointless
  /// without it.
  bool batteryExempt = true;

  DateTime get today => dateOnly(DateTime.now());

  Future<void> load() async {
    loading = true;
    notifyListeners();

    subjects = await db.subjects();
    topics = await db.topics();
    availability = await db.availability();
    prefs = Prefs.fromMap(await db.settings());
    streak = await db.streakEndingAt(today);
    todayLog = await db.logEntriesOn(today);

    await _rebuild();

    loading = false;
    notifyListeners();
  }

  /// Minutes of today already spoken for, whether studied or deliberately
  /// skipped.
  int get consumedToday =>
      todayLog.fold(0, (a, e) => a + e.consumedMinutes);

  Future<void> _rebuild({bool resyncAlarms = true}) async {
    // The planner is stateless, so today's already-spent time has to be
    // expressed as reduced capacity rather than remembered inside it.
    final full = availability.minutesOn(today);
    final left = (full - consumedToday).clamp(0, full);

    final now = DateTime.now();
    plan = planner.generate(
      subjects: subjects,
      topics: topics,
      availability: availability.withOverride(today, left),
      today: today,
      todayStartMinute: now.hour * 60 + now.minute,
    );

    if (resyncAlarms && plan != null) {
      exactAlarmsAllowed = await notifier.canScheduleExact();
      batteryExempt = await notifier.isBatteryExempt();
      await notifier.syncFromPlan(plan!);
    }
  }

  Future<void> refreshAlarms() async {
    exactAlarmsAllowed = await notifier.canScheduleExact();
    batteryExempt = await notifier.isBatteryExempt();
    if (plan != null) await notifier.syncFromPlan(plan!);
    notifyListeners();
  }

  /// Prompts for the battery exemption and re-checks afterwards.
  Future<bool> requestBatteryExemption() async {
    final granted = await notifier.requestBatteryExemption();
    batteryExempt = await notifier.isBatteryExempt();
    notifyListeners();
    return granted;
  }

  // ------------------------------------------------------------- subjects

  Future<void> addSubject({
    required String name,
    DateTime? examDate,
    int weight = 3,
    int color = 0xFF4F46E5,
  }) async {
    final s = Subject(
      id: newId(),
      name: name,
      examDate: examDate,
      weight: weight,
      colorValue: color,
    );
    await db.upsertSubject(s);
    subjects = [...subjects, s]..sort((a, b) => a.name.compareTo(b.name));
    await _rebuild();
    notifyListeners();
  }

  Future<void> updateSubject(Subject s) async {
    await db.upsertSubject(s);
    subjects = [
      for (final x in subjects) x.id == s.id ? s : x,
    ]..sort((a, b) => a.name.compareTo(b.name));
    await _rebuild();
    notifyListeners();
  }

  Future<void> deleteSubject(String id) async {
    await db.deleteSubject(id);
    subjects = subjects.where((s) => s.id != id).toList();
    topics = topics.where((t) => t.subjectId != id).toList();
    await _rebuild();
    notifyListeners();
  }

  Subject? subjectFor(String id) =>
      subjects.where((s) => s.id == id).firstOrNull;

  List<Topic> topicsFor(String subjectId) =>
      topics.where((t) => t.subjectId == subjectId).toList();

  // --------------------------------------------------------------- topics

  Future<void> addTopic({
    required String subjectId,
    required String title,
    required EffortUnit unit,
    required int amount,
    required double rate,
    int difficulty = 3,
    List<String> prerequisiteIds = const [],
  }) async {
    final t = Topic.fromEstimate(
      id: newId(),
      subjectId: subjectId,
      title: title,
      unit: unit,
      amount: amount,
      rate: rate,
      difficulty: difficulty,
      prerequisiteIds: prerequisiteIds,
    );
    await db.upsertTopic(t, sortOrder: topics.length);
    topics = [...topics, t];
    await _rebuild();
    notifyListeners();
  }

  Future<void> updateTopic(Topic t) async {
    await db.upsertTopic(t);
    topics = [for (final x in topics) x.id == t.id ? t : x];
    await _rebuild();
    notifyListeners();
  }

  Future<void> deleteTopic(String id) async {
    await db.deleteTopic(id);
    topics = topics.where((t) => t.id != id).toList();
    await _rebuild();
    notifyListeners();
  }

  // ------------------------------------------------------------- progress

  /// Records a completed block and rolls the plan forward.
  ///
  /// [actualMinutes] defaults to what was planned but should be the real
  /// figure when the student supplies it — that difference is what later
  /// calibrates effort estimates.
  Future<void> markDone(StudySession session, {int? actualMinutes}) async {
    final minutes = actualMinutes ?? session.durationMinutes;
    final topic = topics.where((t) => t.id == session.topicId).firstOrNull;

    if (topic != null && !session.isReview) {
      final completed = topic.completedMinutes + minutes;
      final finished = completed >= topic.estimatedMinutes;
      await updateTopicSilently(topic.copyWith(
        completedMinutes: completed,
        status: finished ? TopicStatus.done : TopicStatus.inProgress,
        firstCompletedOn:
            finished ? (topic.firstCompletedOn ?? today) : topic.firstCompletedOn,
      ));
    }

    await db.logSession(
      session.copyWith(status: SessionStatus.done),
      actualMinutes: minutes,
    );

    todayLog = await db.logEntriesOn(today);
    streak = await db.streakEndingAt(today);
    await _rebuild();
    notifyListeners();
  }

  Future<void> markSkipped(StudySession session) async {
    await db.logSession(
      session.copyWith(status: SessionStatus.skipped),
      actualMinutes: 0,
    );
    todayLog = await db.logEntriesOn(today);
    await _rebuild();
    notifyListeners();
  }

  /// Reverses a logged block.
  ///
  /// Marking done and skipping were both irreversible, so a single mis-tap
  /// permanently corrupted progress and silently consumed the day's capacity.
  /// Undo removes the log entry and, for completed work, gives the minutes back
  /// to the topic.
  Future<void> undoLogged(LoggedSession entry) async {
    if (entry.status == SessionStatus.done && entry.kind != SessionKind.review) {
      final topic = topics.where((t) => t.id == entry.topicId).firstOrNull;
      if (topic != null) {
        final restored =
            (topic.completedMinutes - entry.actualMinutes).clamp(0, 1 << 30);
        await updateTopicSilently(topic.copyWith(
          completedMinutes: restored,
          status: restored == 0
              ? TopicStatus.notStarted
              : (restored >= topic.estimatedMinutes
                  ? TopicStatus.done
                  : TopicStatus.inProgress),
        ));
      }
    }

    await db.deleteLogEntry(entry.id);
    todayLog = await db.logEntriesOn(today);
    streak = await db.streakEndingAt(today);
    await _rebuild();
    notifyListeners();
  }

  /// Reloads if the calendar day has rolled over while the app sat open.
  ///
  /// [today] is computed fresh on every call, but [todayLog] is not: leaving
  /// the app open past midnight showed yesterday's completed blocks as today's
  /// and mis-stated the day's remaining capacity.
  Future<void> refreshIfDayChanged() async {
    final logDay = todayLog.isEmpty ? null : todayLog.first.day;
    if (logDay != null && dateKey(logDay) == dateKey(today)) return;
    todayLog = await db.logEntriesOn(today);
    streak = await db.streakEndingAt(today);
    await _rebuild();
    notifyListeners();
  }

  /// Persists a topic without triggering a replan — used inside operations
  /// that will replan once at the end anyway.
  Future<void> updateTopicSilently(Topic t) async {
    await db.upsertTopic(t);
    topics = [for (final x in topics) x.id == t.id ? t : x];
  }

  // --------------------------------------------------------- availability

  Future<void> setWeekdayMinutes(int weekday, int minutes) async {
    availability = availability.withWeekday(weekday, minutes);
    await db.saveAvailability(availability);
    await _rebuild();
    notifyListeners();
  }

  /// Persists a study-window change and replans against it.
  ///
  /// Rejects an unusable window rather than saving one that would silently
  /// schedule nothing.
  Future<bool> updatePrefs(Prefs next) async {
    if (!next.isUsable) return false;
    prefs = next;
    for (final e in next.toMap().entries) {
      await db.putSetting(e.key, e.value);
    }
    await _rebuild();
    notifyListeners();
    return true;
  }

  Future<void> setDayOverride(DateTime day, int minutes) async {
    availability = availability.withOverride(day, minutes);
    await db.saveAvailability(availability);
    await _rebuild();
    notifyListeners();
  }

  // ------------------------------------------------------------- querying

  /// Today's blocks that are still outstanding. Anything already logged has
  /// been subtracted from capacity, so it no longer appears here.
  List<StudySession> get todaySessions => plan?.onDate(today) ?? const [];

  StudySession? get nextSession => todaySessions.firstOrNull;

  /// The full day: what has been logged plus what remains.
  int get plannedMinutesToday =>
      consumedToday + todaySessions.fold(0, (a, s) => a + s.durationMinutes);

  int get doneMinutesToday => todayLog
      .where((e) => e.status == SessionStatus.done)
      .fold(0, (a, e) => a + e.actualMinutes);

  Feasibility? get feasibility => plan?.feasibility;
}
