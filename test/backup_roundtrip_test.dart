import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/data/backup.dart';
import 'package:prahar/data/database.dart';
import 'package:prahar/domain/models.dart';
import 'package:prahar/domain/schedule.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Does a backup actually come back?
///
/// This is the one feature in the app whose failure is unrecoverable. Every
/// other bug can be fixed in the next build; a restore that silently drops
/// half the data is only discovered once the original is gone. It is also
/// about to be relied on for real: moving from the debug signing key to a
/// release one forces an uninstall, and an uninstall takes the database with
/// it, so export-uninstall-restore is the only path across.
///
/// So: populate every field the export claims to carry, serialise, wipe the
/// database exactly as an uninstall would, restore, and compare field by
/// field. Counting rows would pass while every date came back null.
void main() {
  late Directory dir;
  late PraharDatabase db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('prahar_backup');
    db = PraharDatabase();
    await db.open(path: dir.path);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// Deliberately awkward data: an exam with a known time and one without, a
  /// topic mid-flight with a non-default rate and a link, a prerequisite, a
  /// day off, a weekly commitment and a one-off.
  Future<void> populate() async {
    await db.upsertSubject(
      Subject(
        id: 's1',
        name: 'Physics',
        examDate: DateTime(2026, 10, 12),
        examMinuteOfDay: 9 * 60 + 30,
        weight: 2,
        colorValue: 0xFF4F46E5,
      ),
    );
    await db.upsertSubject(
      Subject(
        id: 's2',
        name: 'Indian Music',
        examDate: DateTime(2026, 11, 3),
        colorValue: 0xFFD97706,
      ),
    );

    await db.upsertTopic(
      const Topic(
        id: 't1',
        subjectId: 's1',
        title: 'Rotational motion',
        estimatedMinutes: 300,
        completedMinutes: 90,
        difficulty: 4,
        estimateUnit: EffortUnit.pages,
        estimateAmount: 60,
        estimateRate: 5.0,
        link: 'https://example.org/rotation',
      ),
    );
    await db.upsertTopic(
      Topic(
        id: 't2',
        subjectId: 's1',
        title: 'Angular momentum',
        estimatedMinutes: 240,
        prerequisiteIds: const ['t1'],
        status: TopicStatus.done,
        firstCompletedOn: DateTime(2026, 9, 1),
      ),
    );
    await db.upsertTopic(
      const Topic(
        id: 't3',
        subjectId: 's2',
        title: 'Raga structure',
        estimatedMinutes: 120,
      ),
    );

    await db.saveAvailability(
      Availability(
        minutesByWeekday: {for (var d = 1; d <= 7; d++) d: 180},
        overrides: {'2026-09-20': 0},
      ),
    );
    await db.upsertBusySlot(
      const BusySlot(
        id: 'b1',
        label: 'Lecture',
        startMinute: 9 * 60,
        endMinute: 11 * 60,
        weekday: DateTime.monday,
      ),
    );
    await db.upsertBusySlot(
      BusySlot(
        id: 'b2',
        label: 'Wedding',
        startMinute: 16 * 60,
        endMinute: 22 * 60,
        date: DateTime(2026, 9, 26),
      ),
    );

    await db.putSetting('material', 'glass');
    await db.putSetting('card_style', 'hairline');
  }

  test('every exported field survives a wipe and a restore', () async {
    await populate();

    final io = BackupIO(db);
    final json = await io.serialise();

    // Exactly what an uninstall does to the local database.
    await db.clearAll();
    expect(await db.subjects(), isEmpty, reason: 'the wipe did not happen');

    final report = await io.import(json);
    expect(report.subjects, 2);
    expect(report.topics, 3);
    expect(report.busy, 2);

    final subjects = await db.subjects();
    final physics = subjects.firstWhere((s) => s.id == 's1');
    expect(physics.name, 'Physics');
    expect(physics.examDate, DateTime(2026, 10, 12));
    expect(physics.examMinuteOfDay, 9 * 60 + 30, reason: 'exam time lost');
    expect(physics.weight, 2);
    expect(physics.colorValue, 0xFF4F46E5);

    // The subject with no exam time must come back with none, rather than
    // acquiring a midnight it never had.
    final music = subjects.firstWhere((s) => s.id == 's2');
    expect(music.examMinuteOfDay, isNull);

    final topics = await db.topics();
    final rotation = topics.firstWhere((t) => t.id == 't1');
    expect(rotation.estimatedMinutes, 300);
    expect(rotation.completedMinutes, 90, reason: 'progress lost');
    expect(rotation.difficulty, 4);
    expect(rotation.estimateUnit, EffortUnit.pages);
    expect(rotation.estimateAmount, 60);
    expect(rotation.estimateRate, 5.0, reason: 'calibrated rate lost');
    expect(rotation.link, 'https://example.org/rotation');

    final angular = topics.firstWhere((t) => t.id == 't2');
    expect(angular.status, TopicStatus.done);
    expect(angular.firstCompletedOn, DateTime(2026, 9, 1));
    expect(angular.prerequisiteIds, ['t1']);

    final avail = await db.availability();
    expect(avail.minutesByWeekday[DateTime.wednesday], 180);
    expect(avail.overrides['2026-09-20'], 0, reason: 'the day off came back');
    expect(avail.busy.length, 2);

    final weekly = avail.busy.firstWhere((b) => b.id == 'b1');
    expect(weekly.weekday, DateTime.monday);
    expect(weekly.startMinute, 9 * 60);
    expect(weekly.label, 'Lecture');

    final oneOff = avail.busy.firstWhere((b) => b.id == 'b2');
    expect(oneOff.weekday, isNull);
    expect(oneOff.date, DateTime(2026, 9, 26));

    final settings = await db.settings();
    expect(settings['material'], 'glass');
    expect(settings['card_style'], 'hairline');
  });

  test('a file written to disk is what gets restored', () async {
    await populate();

    // exportToFile is the path the Settings button actually takes; serialise()
    // being correct proves nothing about what lands on the card.
    final path = await BackupIO(db).exportToFile();
    expect(File(path).existsSync(), isTrue);

    await db.clearAll();
    await BackupIO(db).import(await File(path).readAsString());

    expect((await db.subjects()).length, 2);
    expect((await db.topics()).length, 3);

    File(path).deleteSync();
  });

  test('the session log is NOT carried, and that is worth knowing', () async {
    await populate();
    await db.logSession(
      StudySession(
        id: 'x1',
        topicId: 't1',
        subjectId: 's1',
        subjectName: 'Physics',
        topicTitle: 'Rotational motion',
        date: DateTime(2026, 9, 4),
        startMinuteOfDay: 600,
        durationMinutes: 45,
        status: SessionStatus.done,
      ),
      actualMinutes: 45,
    );

    expect((await db.logEntriesOn(DateTime(2026, 9, 4))).length, 1);

    final io = BackupIO(db);
    final json = await io.serialise();
    await db.clearAll();
    await io.import(json);

    // Restoring does not bring history back. `completedMinutes` on the topic
    // survives, so the plan and the progress figures are right; what is lost
    // is the audit trail behind them — the streak, and the per-subject
    // calibration samples that need three finished topics to say anything.
    //
    // Pinned rather than fixed: exporting the log is a format change, and the
    // decision of whether history is worth carrying is the user's. This test
    // exists so nobody is surprised by it at the moment of restoring.
    expect(await db.logEntriesOn(DateTime(2026, 9, 4)), isEmpty);
    expect((await db.topics()).firstWhere((t) => t.id == 't1').completedMinutes,
        90);
  });
}
