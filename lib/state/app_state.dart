import 'dart:math';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../data/database.dart';
import '../domain/background_limits.dart';
import '../domain/models.dart';
import '../domain/preferences.dart';
import '../domain/schedule.dart';
import '../planner/calibration.dart';
import '../notifications/notifier.dart';
import '../notifications/widget_bridge.dart';
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

  /// The vendor autostart gate this phone has, if any.
  ///
  /// Null on a Pixel and on anything unrecognised. Read once at load rather
  /// than on every replan: the manufacturer does not change under a running
  /// app, and this is a platform channel call.
  ///
  /// Note this says nothing about whether autostart is *on*. Android exposes
  /// no way to ask. See [BackgroundGate].
  BackgroundGate? backgroundGate;

  /// The block the student actually started, if any.
  ///
  /// This is what separates a block in progress from a block that has merely
  /// been sitting there. Nothing else in the app records it: `session_log`
  /// only learns about a block once it is finished or skipped, and sessions
  /// themselves are regenerated on every replan and cannot hold state.
  ///
  /// Persisted in `settings` rather than as a column, because it is one
  /// string about right now, not history, and it must survive the process
  /// being killed mid-block — which on these phones is routine.
  String? runningSessionId;

  /// How far a block may start in the past before the day is re-anchored.
  ///
  /// Not zero. Re-anchoring on every tick would drag the whole day forward a
  /// minute per minute: the block would restart at "now" forever, never
  /// elapse, and its countdown would never move. A couple of minutes of slack
  /// is invisible to read and keeps the replan, and the alarm resync behind
  /// it, down to something occasional.
  static const reanchorAfterMinutes = 2;

  /// Whether to show the autostart notice.
  ///
  /// Deliberately behind the battery warning: while that one is up it is the
  /// more important of the two and stacking a second card underneath it splits
  /// the attention it needs. This one waits its turn.
  bool get showAutostartNotice {
    if (backgroundGate == null) return false;
    if (!batteryExempt) return false;
    if (prefs.autostartDismissed) return false;

    final until = prefs.autostartSnoozedUntil;
    // "Not now" means not now, so the card stays away until the day it said
    // it would come back. Showing on that day, not after it, or a one-day
    // snooze would be a two-day one.
    if (until != null && today.isBefore(until)) return false;

    return true;
  }

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
    // hasAutostartScreen decides whether there is a gate; the manufacturer
    // only picks the wording. See BackgroundGate.resolve.
    // Empty string means nothing running; the settings table has no nulls.
    final running = (await db.settings())['running_session'] ?? '';
    runningSessionId = running.isEmpty ? null : running;

    backgroundGate = BackgroundGate.resolve(
      manufacturer: await notifier.deviceVendor(),
      hasScreen: await notifier.hasAutostartScreen(),
    );

    await _rebuild();

    loading = false;
    notifyListeners();
  }

  /// Minutes of today already spoken for, whether studied or deliberately
  /// skipped.
  int get consumedToday => todayLog.fold(0, (a, e) => a + e.consumedMinutes);

  /// Recommendations the app can currently offer, e.g. "your Chemistry pages
  /// actually take 4.5 min each".
  ///
  /// Held here rather than computed where it is drawn. Progress used to call
  /// the query version straight from `build`, which meant a database read on
  /// every rebuild — and since every `notifyListeners` rebuilds Progress, that
  /// was a read per edit, per tap, per minute tick. It also handed
  /// `FutureBuilder` a new future each time, so the card blinked out and back
  /// on unrelated changes, and it left a pending query behind in widget tests
  /// that failed something else with a stack naming sqflite.
  ///
  /// Recomputed in [_rebuild], which already runs on every change, so this is
  /// as fresh as the plan is.
  List<CalibrationSuggestion> calibration = const [];

  Future<List<CalibrationSuggestion>> _computeCalibration() async {
    final ids = topics.map((t) => t.id);
    final completed = await db.completedFor(ids);
    return const Calibrator().analyse(topics: topics, completed: completed);
  }

  /// Applies a recommendation — updates the rate on every affected topic and
  /// recomputes its estimated minutes so the schedule reflects the new
  /// reality. Progress in minutes is preserved rather than proportion, because
  /// the user has spent real time; the estimate becomes more truthful, not the
  /// history.
  Future<void> applyCalibration(CalibrationSuggestion s) async {
    for (final id in s.affectedTopicIds) {
      final t = topics.firstWhere((x) => x.id == id);
      final newMinutes = (t.estimateAmount * s.recommendedRate).round().clamp(
        1,
        1 << 30,
      );
      await updateTopicSilently(
        t.copyWith(
          estimateRate: s.recommendedRate,
          estimatedMinutes: newMinutes,
        ),
      );
    }
    await _rebuild();
    notifyListeners();
  }

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

    // One query per replan, not one per rebuild. It reads the same completed
    // topics the planner just used, so this is the moment it is cheapest and
    // the moment it is guaranteed to be in step with the plan.
    calibration = await _computeCalibration();

    if (resyncAlarms && plan != null) {
      exactAlarmsAllowed = await notifier.canScheduleExact();
      batteryExempt = await notifier.isBatteryExempt();
      // A replan is worth doing even if the alarms cannot be written: the
      // schedule on screen is still correct, and throwing here would take the
      // whole edit down with it. There is no plugin behind the channel in a
      // test, which is exactly what this used to trip over.
      try {
        await notifier.syncFromPlan(plan!);
        await _syncDigests();
      } catch (e) {
        debugPrint('Prahar: could not resync alarms: $e');
      }
    }

    // Keep the home-screen widgets in step. Cheap; runs on every replan.
    // done/planned drive the progress bar on the wider widget.
    if (plan != null) {
      await WidgetBridge.updateNextBlock(
        plan!.onDate(today),
        doneMinutes: doneMinutesToday,
        plannedMinutes: plannedMinutesToday,
      );
    }
  }

  Future<void> refreshAlarms() async {
    exactAlarmsAllowed = await notifier.canScheduleExact();
    batteryExempt = await notifier.isBatteryExempt();
    if (plan != null) await notifier.syncFromPlan(plan!);
    await _syncDigests();
    notifyListeners();
  }

  /// Queues one evening summary per night, each describing the day after it.
  ///
  /// Written out per evening rather than as a single repeating alarm because a
  /// repeat carries the same text forever: right the first night, and wrong
  /// every night after. Refreshed on every replan and every app resume, so the
  /// summaries stay true as the plan changes under them.
  Future<void> _syncDigests() async {
    if (!prefs.digestEnabled || plan == null) {
      await notifier.syncDigests(const []);
      return;
    }

    final entries = <({DateTime when, String body})>[];
    for (var i = 0; i < Notifier.digestDays; i++) {
      // Constructor arithmetic, not Duration — adding 24 hours drifts off
      // midnight across a DST boundary and lands two evenings on one date.
      final evening = DateTime(
        today.year,
        today.month,
        today.day + i,
        prefs.digestMinute ~/ 60,
        prefs.digestMinute % 60,
      );
      final tomorrow = DateTime(today.year, today.month, today.day + i + 1);
      entries.add((when: evening, body: plan!.digestFor(tomorrow)));
    }

    await notifier.syncDigests(entries);
  }

  // ------------------------------------------------- keeping today honest

  /// Records that the student has actually begun a block.
  ///
  /// Called when the focus timer starts, which is the only moment the app
  /// knows the difference between "this is the block you are on" and "this is
  /// the block you were offered and ignored".
  Future<void> beginSession(StudySession s) async {
    if (runningSessionId == s.id) return;
    runningSessionId = s.id;
    notifyListeners();
    await db.putSetting('running_session', s.id);
  }

  /// Forgets the running block, so the day is free to move again.
  Future<void> endSession() async {
    if (runningSessionId == null) return;
    runningSessionId = null;
    notifyListeners();
    await db.putSetting('running_session', '');
  }

  /// Pulls the day forward so nothing is offered from the past.
  ///
  /// A plan is generated from the moment it is made, so opening the app at
  /// 11:16 gives a block at 11:16. Nothing replanned it after that, so by
  /// 11:46 the same block still read 11:35, and the student was looking at a
  /// schedule that had quietly expired.
  ///
  /// Only when nothing is running. A block that has been started keeps its
  /// original start time, because that is what makes "29m left" mean anything
  /// and what stops the countdown resetting every time the clock ticks.
  /// Driven by Today's existing one-minute timer.
  Future<void> reanchorIfIdle() async {
    if (loading || plan == null) return;
    if (runningSessionId != null) return;

    final now = DateTime.now();
    final nowMinute = now.hour * 60 + now.minute;
    final logged = todayLog.map((e) => e.id).toSet();

    final stale = plan!
        .onDate(today)
        .where((s) => !logged.contains(s.id))
        .any((s) => nowMinute - s.startMinuteOfDay >= reanchorAfterMinutes);
    if (!stale) return;

    // With the alarm resync: today's blocks have just moved, so the reminders
    // pointing at their old times are now wrong. The threshold above is what
    // keeps this from running every minute.
    await _rebuild();
    notifyListeners();
  }

  /// Opens the vendor's autostart screen and retires the notice.
  ///
  /// Retired whether or not the screen opened, and without waiting to see what
  /// was done there, because there is nothing to wait for: no API reports
  /// autostart state, so the app cannot tell success from a student who backed
  /// straight out. Showing it again on that guess would be nagging.
  Future<AutostartOpen> openAutostartSettings() async {
    final outcome = await notifier.openAutostartSettings();
    await dismissAutostartNotice();
    return outcome;
  }

  /// Puts the notice away for a day or so, which is what "Not now" says.
  ///
  /// The wait grows each time — 1 day, then 3, then 7 — and after the last
  /// rung the notice retires itself. A button that honestly means "later" has
  /// to come back or the label is a lie, but the app cannot check whether
  /// autostart was ever turned on, so it has no way to notice it is asking a
  /// question that has already been answered. The ladder is what bounds that:
  /// four showings over eleven days, then silence.
  Future<void> snoozeAutostartNotice() async {
    const ladder = Prefs.autostartSnoozeLadder;
    final n = prefs.autostartSnoozeCount;
    if (n >= ladder.length) {
      await dismissAutostartNotice();
      return;
    }

    // Constructor arithmetic, not Duration: adding 24 hours lands an hour
    // early across a DST boundary and the notice returns a day late.
    final until = DateTime(today.year, today.month, today.day + ladder[n]);

    prefs = prefs.copyWith(
      autostartSnoozeCount: n + 1,
      autostartSnoozedUntil: until,
    );
    notifyListeners();

    await db.putSetting('autostart_snooze_count', '${n + 1}');
    await db.putSetting('autostart_snoozed_until', Prefs.isoDate(until));
  }

  /// Retires the notice now and records it afterwards.
  ///
  /// The order matters: notifying first takes the card off the screen on the
  /// tap, rather than after a disk round trip. Dismissing a card and watching
  /// it sit there is the kind of lag that reads as a broken button, and there
  /// is nothing here worth waiting on — the write cannot fail in a way the
  /// student could act on.
  Future<void> dismissAutostartNotice() async {
    if (prefs.autostartDismissed) return;
    prefs = prefs.copyWith(autostartDismissed: true);
    notifyListeners();
    await db.putSetting('autostart_dismissed', '1');
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
    int? examMinuteOfDay,
    int weight = 3,
    int color = 0xFF4F46E5,
  }) async {
    final s = Subject(
      id: newId(),
      name: name,
      examDate: examDate,
      examMinuteOfDay: examMinuteOfDay,
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
    subjects = [for (final x in subjects) x.id == s.id ? s : x]
      ..sort((a, b) => a.name.compareTo(b.name));
    await _rebuild();
    notifyListeners();
  }

  /// Removes a subject everywhere: the row, its topics by cascade, and its
  /// history in the log.
  ///
  /// The log has no foreign key — it is an audit trail, and outliving the
  /// topic it describes is the point — so nothing cascaded into it. A deleted
  /// subject therefore went on showing in today's list and counting towards
  /// the streak, which is not what deleting something means.
  Future<void> deleteSubject(String id) async {
    await db.deleteSubject(id);
    await db.deleteLogForSubject(id);
    subjects = subjects.where((s) => s.id != id).toList();
    topics = topics.where((t) => t.subjectId != id).toList();
    todayLog = await db.logEntriesOn(today);
    streak = await db.streakEndingAt(today);
    await _rebuild();
    notifyListeners();
  }

  Subject? subjectFor(String id) =>
      subjects.where((s) => s.id == id).firstOrNull;

  List<Topic> topicsFor(String subjectId) =>
      topics.where((t) => t.subjectId == subjectId).toList();

  /// Subjects whose exam is in the past.
  ///
  /// The planner already refuses to schedule them, but they still occupy a row
  /// in the Subjects list and generate feasibility warnings you cannot act on.
  /// A subject is "archived" simply by being past its exam date — there is no
  /// separate flag, so the state is always accurate and cannot fall out of
  /// sync with the deadline the user set.
  List<Subject> get archivedSubjects {
    final today = dateOnly(DateTime.now());
    return subjects
        .where((s) => s.examDate != null && s.examDate!.isBefore(today))
        .toList()
      ..sort((a, b) => b.examDate!.compareTo(a.examDate!));
  }

  List<Subject> get activeSubjects {
    final today = dateOnly(DateTime.now());
    return subjects
        .where((s) => s.examDate == null || !s.examDate!.isBefore(today))
        .toList();
  }

  // --------------------------------------------------------------- topics

  Future<void> addTopic({
    required String subjectId,
    required String title,
    required EffortUnit unit,
    required int amount,
    required double rate,
    int difficulty = 3,
    List<String> prerequisiteIds = const [],
    String? link,
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
    ).copyWith(link: link);
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

  /// Clones a topic verbatim, appending "(copy)" and resetting completion.
  ///
  /// Students add "Ch 4", "Ch 5", "Ch 6" in a row — same book, same page
  /// count, incremented number. Duplicate + edit the title beats re-entering
  /// unit / amount / difficulty every time.
  Future<Topic> duplicateTopic(Topic source) async {
    final made = Topic(
      id: newId(),
      subjectId: source.subjectId,
      title: '${source.title} (copy)',
      estimatedMinutes: source.estimatedMinutes,
      difficulty: source.difficulty,
      prerequisiteIds: source.prerequisiteIds,
      estimateUnit: source.estimateUnit,
      estimateAmount: source.estimateAmount,
      estimateRate: source.estimateRate,
    );
    await db.upsertTopic(made, sortOrder: topics.length);
    topics = [...topics, made];
    await _rebuild();
    notifyListeners();
    return made;
  }

  // ------------------------------------------------------------- progress

  /// Records a completed block and rolls the plan forward.
  ///
  /// [actualMinutes] defaults to what was planned but should be the real
  /// figure when the student supplies it — that difference is what later
  /// calibrates effort estimates.
  Future<void> markDone(StudySession session, {int? actualMinutes}) async {
    // Whatever was running is over. Without this the day stays pinned to a
    // block that has already been logged and never re-anchors again.
    if (runningSessionId == session.id) await endSession();
    final minutes = actualMinutes ?? session.durationMinutes;
    final topic = topics.where((t) => t.id == session.topicId).firstOrNull;

    if (topic != null && !session.isReview) {
      final completed = topic.completedMinutes + minutes;
      final finished = completed >= topic.estimatedMinutes;
      await updateTopicSilently(
        topic.copyWith(
          completedMinutes: completed,
          status: finished ? TopicStatus.done : TopicStatus.inProgress,
          firstCompletedOn: finished
              ? (topic.firstCompletedOn ?? today)
              : topic.firstCompletedOn,
        ),
      );
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
    if (runningSessionId == session.id) await endSession();
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
    if (entry.status == SessionStatus.done &&
        entry.kind != SessionKind.review) {
      final topic = topics.where((t) => t.id == entry.topicId).firstOrNull;
      if (topic != null) {
        final restored = (topic.completedMinutes - entry.actualMinutes).clamp(
          0,
          1 << 30,
        );
        await updateTopicSilently(
          topic.copyWith(
            completedMinutes: restored,
            status: restored == 0
                ? TopicStatus.notStarted
                : (restored >= topic.estimatedMinutes
                      ? TopicStatus.done
                      : TopicStatus.inProgress),
          ),
        );
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

  Future<void> addBusySlot(BusySlot s) async {
    await db.upsertBusySlot(s);
    availability = availability.withBusy([...availability.busy, s]);
    await _rebuild();
    notifyListeners();
  }

  Future<void> updateBusySlot(BusySlot s) async {
    await db.upsertBusySlot(s);
    availability = availability.withBusy([
      for (final x in availability.busy) x.id == s.id ? s : x,
    ]);
    await _rebuild();
    notifyListeners();
  }

  Future<void> deleteBusySlot(String id) async {
    await db.deleteBusySlot(id);
    availability = availability.withBusy(
      availability.busy.where((b) => b.id != id).toList(),
    );
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
