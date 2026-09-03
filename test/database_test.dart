import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:prahar/data/database.dart';
import 'package:prahar/domain/models.dart';
import 'package:prahar/domain/schedule.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// These exist because of a real data-loss bug found on a device, not in
/// testing: `ConflictAlgorithm.replace` compiles to `INSERT OR REPLACE`, which
/// DELETEs the conflicting row before inserting. Combined with
/// `PRAGMA foreign_keys = ON` and `ON DELETE CASCADE`, saving an edited subject
/// silently wiped every topic under it.
///
/// The failure is invisible at the call site — the write "succeeds" — so only a
/// test that edits a parent and then counts its children can catch it.
void main() {
  late Directory dir;
  late PraharDatabase db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('prahar_test');
    db = PraharDatabase();
    await db.open(path: dir.path);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Subject subject({String id = 's1', String name = 'Physics', int weight = 3}) =>
      Subject(id: id, name: name, weight: weight);

  Topic topic({
    String id = 't1',
    String subjectId = 's1',
    String title = 'Kinematics',
    int minutes = 120,
  }) =>
      Topic(
        id: id,
        subjectId: subjectId,
        title: title,
        estimatedMinutes: minutes,
      );

  group('editing must not destroy children', () {
    test('editing a subject keeps its topics', () async {
      await db.upsertSubject(subject());
      await db.upsertTopic(topic());
      await db.upsertTopic(topic(id: 't2', title: 'Dynamics'));
      expect((await db.topicsFor('s1')).length, 2);

      // The exact operation that used to wipe them.
      await db.upsertSubject(subject(name: 'Physics I', weight: 5));

      final topics = await db.topicsFor('s1');
      expect(topics.length, 2, reason: 'editing a subject deleted its topics');
      expect((await db.subjects()).single.name, 'Physics I');
      expect((await db.subjects()).single.weight, 5);
    });

    test('editing a topic keeps its resources', () async {
      await db.upsertSubject(subject());
      await db.upsertTopic(topic());
      await db.upsertResource(const Resource(
        id: 'r1',
        topicId: 't1',
        kind: ResourceKind.book,
        title: 'HC Verma',
        pageStart: 1,
        pageEnd: 40,
      ));
      expect((await db.resourcesFor('t1')).length, 1);

      await db.upsertTopic(topic(title: 'Kinematics revised', minutes: 200));

      expect((await db.resourcesFor('t1')).length, 1,
          reason: 'editing a topic deleted its resources');
      final t = (await db.topicsFor('s1')).single;
      expect(t.title, 'Kinematics revised');
      expect(t.estimatedMinutes, 200);
    });

    test('repeated edits are still non-destructive', () async {
      await db.upsertSubject(subject());
      await db.upsertTopic(topic());

      for (var i = 0; i < 5; i++) {
        await db.upsertSubject(subject(name: 'Physics $i'));
        await db.upsertTopic(topic(title: 'Kinematics $i'));
      }

      expect((await db.topicsFor('s1')).length, 1);
      expect((await db.subjects()).length, 1);
    });
  });

  group('deletes still cascade on purpose', () {
    test('deleting a subject removes its topics', () async {
      await db.upsertSubject(subject());
      await db.upsertTopic(topic());

      await db.deleteSubject('s1');

      expect(await db.subjects(), isEmpty);
      expect(await db.topics(), isEmpty,
          reason: 'an explicit subject delete should still cascade');
    });

    test('deleting a topic removes its resources', () async {
      await db.upsertSubject(subject());
      await db.upsertTopic(topic());
      await db.upsertResource(const Resource(
        id: 'r1',
        topicId: 't1',
        kind: ResourceKind.url,
        title: 'notes',
      ));

      await db.deleteTopic('t1');
      expect(await db.resourcesFor('t1'), isEmpty);
    });
  });

  group('round trips', () {
    test('subject fields survive a save and load', () async {
      final exam = DateTime(2026, 10, 24);
      await db.upsertSubject(Subject(
        id: 's1',
        name: 'DSA',
        examDate: exam,
        weight: 4,
        colorValue: 0xFFD97706,
      ));

      final s = (await db.subjects()).single;
      expect(s.name, 'DSA');
      expect(s.examDate, exam);
      expect(s.weight, 4);
      expect(s.colorValue, 0xFFD97706);
    });

    test('topic prerequisites survive as a list', () async {
      await db.upsertSubject(subject());
      await db.upsertTopic(Topic(
        id: 't2',
        subjectId: 's1',
        title: 'Advanced',
        estimatedMinutes: 60,
        prerequisiteIds: const ['t1', 'tx'],
        status: TopicStatus.inProgress,
        completedMinutes: 30,
      ));

      final t = (await db.topicsFor('s1')).single;
      expect(t.prerequisiteIds, ['t1', 'tx']);
      expect(t.status, TopicStatus.inProgress);
      expect(t.completedMinutes, 30);
    });

    test('a topic with no prerequisites loads as an empty list', () async {
      await db.upsertSubject(subject());
      await db.upsertTopic(topic());
      expect((await db.topicsFor('s1')).single.prerequisiteIds, isEmpty);
    });

    test('availability overrides round trip', () async {
      final day = DateTime(2026, 9, 5);
      await db.saveAvailability(
        Availability.standard().withOverride(day, 0).withWeekday(1, 90),
      );

      final a = await db.availability();
      expect(a.minutesOn(day), 0);
      expect(a.minutesByWeekday[1], 90);
    });
  });

  group('estimate provenance', () {
    test('the unit and figure entered survive a save and load', () async {
      await db.upsertSubject(subject());
      await db.upsertTopic(Topic.fromEstimate(
        id: 't1',
        subjectId: 's1',
        title: 'Ch 4',
        unit: EffortUnit.pages,
        amount: 200,
        rate: 3.0,
      ));

      final t = (await db.topicsFor('s1')).single;
      expect(t.estimateUnit, EffortUnit.pages);
      expect(t.estimateAmount, 200, reason: 'the typed figure must persist');
      expect(t.estimateRate, 3.0);
      expect(t.estimatedMinutes, 600);
      expect(t.estimateLabel, '200 pages');
    });

    test('minutes-entered topics round trip unchanged', () async {
      await db.upsertSubject(subject());
      await db.upsertTopic(Topic.fromEstimate(
        id: 't1',
        subjectId: 's1',
        title: 'Revision',
        unit: EffortUnit.minutes,
        amount: 90,
        rate: 1.0,
      ));

      final t = (await db.topicsFor('s1')).single;
      expect(t.estimatedMinutes, 90);
      expect(t.estimateAmount, 90);
      expect(t.estimateUnit, EffortUnit.minutes);
    });
  });

  group('migration from v1', () {
    test('adds estimate columns and backfills existing rows', () async {
      // Build a database with the v1 schema, exactly as it shipped.
      final dir2 = await Directory.systemTemp.createTemp('prahar_v1');
      final path = p.join(dir2.path, 'prahar.db');

      final v1 = await databaseFactory.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (d, _) async {
            await d.execute('''
              CREATE TABLE subjects (
                id TEXT PRIMARY KEY, name TEXT NOT NULL, exam_date TEXT,
                weight INTEGER NOT NULL DEFAULT 3, color INTEGER NOT NULL)''');
            await d.execute('''
              CREATE TABLE topics (
                id TEXT PRIMARY KEY,
                subject_id TEXT NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
                title TEXT NOT NULL,
                estimated_minutes INTEGER NOT NULL,
                completed_minutes INTEGER NOT NULL DEFAULT 0,
                difficulty INTEGER NOT NULL DEFAULT 3,
                prerequisite_ids TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL DEFAULT 'notStarted',
                first_completed_on TEXT,
                sort_order INTEGER NOT NULL DEFAULT 0)''');
            await d.insert('subjects',
                {'id': 's1', 'name': 'Physics', 'weight': 3, 'color': 1});
            await d.insert('topics', {
              'id': 't1',
              'subject_id': 's1',
              'title': 'Old topic',
              'estimated_minutes': 450,
              'completed_minutes': 120,
            });
          },
        ),
      );
      await v1.close();

      // Reopening through the real class must upgrade, not wipe.
      final upgraded = PraharDatabase();
      await upgraded.open(path: dir2.path);

      final topics = await upgraded.topicsFor('s1');
      expect(topics.length, 1, reason: 'migration must not lose rows');

      final t = topics.single;
      expect(t.title, 'Old topic');
      expect(t.estimatedMinutes, 450);
      expect(t.completedMinutes, 120, reason: 'progress must survive');
      expect(t.estimateUnit, EffortUnit.minutes,
          reason: 'pre-v2 rows were entered as minutes');
      expect(t.estimateAmount, 450, reason: 'backfilled from the minutes');
      expect(t.estimateRate, 1.0);

      // The settings table the study window needs must now exist.
      await upgraded.putSetting('day_start', '480');
      expect((await upgraded.settings())['day_start'], '480');

      await upgraded.close();
      dir2.deleteSync(recursive: true);
    });

    test('upgrading twice is harmless', () async {
      await db.upsertSubject(subject());
      await db.upsertTopic(topic());
      // open() already ran the migration; running the whole flow again on the
      // same file must not throw on duplicate columns.
      final again = PraharDatabase();
      await again.open(path: dir.path);
      expect((await again.topicsFor('s1')).length, 1);
      await again.close();
    });
  });

  group('settings', () {
    test('round trip and overwrite', () async {
      await db.putSetting('block_minutes', '45');
      await db.putSetting('block_minutes', '30');
      final s = await db.settings();
      expect(s['block_minutes'], '30');
      expect(s.length, 1, reason: 'overwriting must not duplicate the key');
    });
  });

  group('session log', () {
    StudySession session({String id = 'n|2026-09-03|360|t1'}) => StudySession(
          id: id,
          topicId: 't1',
          subjectId: 's1',
          topicTitle: 'Kinematics',
          subjectName: 'Physics',
          date: DateTime(2026, 9, 3),
          startMinuteOfDay: 360,
          durationMinutes: 50,
          status: SessionStatus.done,
        );

    test('logging twice with the same id updates rather than duplicates',
        () async {
      await db.logSession(session(), actualMinutes: 50);
      await db.logSession(session(), actualMinutes: 65);

      final entries = await db.logEntriesOn(DateTime(2026, 9, 3));
      expect(entries.length, 1);
      expect(entries.single.actualMinutes, 65);
    });

    test('a skipped block consumes its planned time, a done one its actual',
        () async {
      await db.logSession(
        session().copyWith(status: SessionStatus.skipped),
        actualMinutes: 0,
      );
      final e = (await db.logEntriesOn(DateTime(2026, 9, 3))).single;
      expect(e.wasSkipped, isTrue);
      expect(e.consumedMinutes, 50);
    });

    test('streak counts consecutive days back from today', () async {
      for (var i = 0; i < 3; i++) {
        final day = DateTime(2026, 9, 3).subtract(Duration(days: i));
        await db.logSession(
          StudySession(
            id: 'n|$i',
            topicId: 't1',
            subjectId: 's1',
            topicTitle: 'x',
            subjectName: 'y',
            date: day,
            startMinuteOfDay: 360,
            durationMinutes: 30,
            status: SessionStatus.done,
          ),
          actualMinutes: 30,
        );
      }
      // Gap: nothing logged 4 days back.
      expect(await db.streakEndingAt(DateTime(2026, 9, 3)), 3);
    });
  });
}
