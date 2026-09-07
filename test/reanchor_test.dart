import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/data/database.dart';
import 'package:prahar/domain/models.dart';
import 'package:prahar/domain/preferences.dart';
import 'package:prahar/domain/schedule.dart';
import 'package:prahar/notifications/notifier.dart';
import 'package:prahar/planner/planner.dart';
import 'package:prahar/state/app_state.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Today is generated from the moment it is planned, and nothing replanned it
/// afterwards.
///
/// Seen on a tablet: opening the app at 11:16 gave a block at 11:16, and by
/// 11:46 the same block still read 11:35. The student was looking at a
/// schedule that had quietly expired.
///
/// The obvious fix is worse than the bug, and these tests exist mostly to hold
/// that line. Re-anchoring on every tick drags the whole day forward a minute
/// per minute: the block restarts at "now" forever, never elapses, and the
/// countdown never moves. So the rule is narrower — pull the day forward only
/// while nothing is actually running, and only once the drift is worth acting
/// on.
void main() {
  late Directory dir;
  late PraharDatabase db;
  late AppState state;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// A plan whose first block began [minutesAgo] before now, as though it had
  /// been generated then and left alone since.
  Future<void> planAsOf(int minutesAgo) async {
    final now = DateTime.now();
    final then = now.subtract(Duration(minutes: minutesAgo));

    state.plan = const Planner().generate(
      subjects: state.subjects,
      topics: state.topics,
      availability: state.availability,
      today: DateTime(now.year, now.month, now.day),
      todayStartMinute: then.hour * 60 + then.minute,
    );
  }

  int firstStart() => state.plan!.onDate(state.today).first.startMinuteOfDay;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('prahar_reanchor');
    db = PraharDatabase();
    await db.open(path: dir.path);

    // Written to the database, not just held in memory: markDone updates the
    // topic, and topics carry a foreign key to subjects, so an in-memory-only
    // fixture fails on the write rather than on anything being tested.
    final subject = Subject(
      id: 's1',
      name: 'Operating Systems',
      examDate: DateTime.now().add(const Duration(days: 15)),
      colorValue: 0xFF4F46E5,
    );
    const topic = Topic(
      id: 't1',
      subjectId: 's1',
      title: 'Virtualization',
      estimatedMinutes: 600,
    );
    await db.upsertSubject(subject);
    await db.upsertTopic(topic);

    state = AppState(db: db, notifier: Notifier())
      ..loading = false
      ..prefs = const Prefs()
      ..subjects = [subject]
      ..topics = [topic]
      ..availability = Availability(
        minutesByWeekday: {for (var d = 1; d <= 7; d++) d: 480},
      );
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test('a plan that has fallen behind the clock is pulled forward', () async {
    await planAsOf(30);
    final before = firstStart();

    await state.reanchorIfIdle();

    expect(
      firstStart(),
      greaterThan(before),
      reason: 'a block half an hour in the past is not a plan',
    );
  });

  test('a fresh plan is left alone', () async {
    await planAsOf(0);
    final before = firstStart();

    await state.reanchorIfIdle();

    expect(firstStart(), before);
  });

  test('a minute of drift is not worth moving the day for', () async {
    // Under the threshold. Without this the day would shift on every tick.
    await planAsOf(1);
    final before = firstStart();

    await state.reanchorIfIdle();

    expect(firstStart(), before);
  });

  test('a started block keeps its start time', () async {
    await planAsOf(30);
    final session = state.plan!.onDate(state.today).first;
    final before = session.startMinuteOfDay;

    await state.beginSession(session);
    await state.reanchorIfIdle();

    expect(
      firstStart(),
      before,
      reason: 'moving a running block resets its countdown every minute',
    );
  });

  test('the day moves again once the block is finished with', () async {
    await planAsOf(30);
    final session = state.plan!.onDate(state.today).first;

    await state.beginSession(session);
    await state.reanchorIfIdle();
    final pinned = firstStart();

    await state.endSession();
    await state.reanchorIfIdle();

    expect(firstStart(), greaterThan(pinned));
  });

  test('re-anchoring twice in a row does not keep shifting the day', () async {
    // The failure mode this whole design exists to avoid: a block that
    // re-anchors to "now" on every pass never elapses, so the student can
    // watch it forever and never make progress.
    await planAsOf(30);

    await state.reanchorIfIdle();
    final settled = firstStart();

    await state.reanchorIfIdle();

    expect(
      firstStart(),
      settled,
      reason: 'the day chases the clock instead of settling on it',
    );
  });

  test('what is running survives a restart', () async {
    await planAsOf(30);
    final session = state.plan!.onDate(state.today).first;
    await state.beginSession(session);

    // Android kills the process mid-block routinely, and coming back to a day
    // that had forgotten what was running would move the block under the
    // student's feet.
    final reread = (await db.settings())['running_session'];
    expect(reread, session.id);
  });

  test('finishing a block clears what was running', () async {
    await planAsOf(30);
    final session = state.plan!.onDate(state.today).first;
    await state.beginSession(session);

    await state.markDone(session, actualMinutes: 20);

    expect(state.runningSessionId, isNull);
  });

  test('skipping a block clears what was running', () async {
    await planAsOf(30);
    final session = state.plan!.onDate(state.today).first;
    await state.beginSession(session);

    await state.markSkipped(session);

    expect(state.runningSessionId, isNull);
  });
}
