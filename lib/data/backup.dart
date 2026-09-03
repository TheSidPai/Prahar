import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/models.dart';
import '../domain/schedule.dart';
import 'database.dart';

/// One-file JSON dump of the local state.
///
/// A backup rather than a sync: the file lives on the device's shared storage,
/// the user hands it around themselves. Local-first means this is the whole
/// story for recovery — a lost phone is a lost app without it, so it exists.
///
/// The format is a single object with a version number, so a later change of
/// shape can still read yesterday's export. Additive changes bump the format;
/// destructive ones need a migration in [BackupIO.import] before touching the
/// database.
class BackupIO {
  BackupIO(this.db);

  final PraharDatabase db;

  static const _formatVersion = 1;

  /// Serialises everything the app persists into a single JSON string.
  ///
  /// [DateTime]s become `yyyy-mm-dd` keys via [dateKey] so an export from one
  /// timezone imports cleanly into another — a full ISO-8601 string would drag
  /// UTC offsets that a schedule does not care about.
  Future<String> serialise() async {
    final subjects = await db.subjects();
    final topics = await db.topics();
    final avail = await db.availability();
    final settings = await db.settings();

    Object? d(DateTime? v) => v == null ? null : dateKey(v);

    return const JsonEncoder.withIndent('  ').convert({
      'format': _formatVersion,
      'exported_at': DateTime.now().toIso8601String(),
      'subjects': [
        for (final s in subjects)
          {
            'id': s.id,
            'name': s.name,
            'exam_date': d(s.examDate),
            'weight': s.weight,
            'color': s.colorValue,
          }
      ],
      'topics': [
        for (final t in topics)
          {
            'id': t.id,
            'subject_id': t.subjectId,
            'title': t.title,
            'estimated_minutes': t.estimatedMinutes,
            'completed_minutes': t.completedMinutes,
            'difficulty': t.difficulty,
            'prerequisite_ids': t.prerequisiteIds,
            'status': t.status.name,
            'first_completed_on': d(t.firstCompletedOn),
            'estimate_unit': t.estimateUnit.name,
            'estimate_amount': t.estimateAmount,
            'estimate_rate': t.estimateRate,
            'link': t.link,
          }
      ],
      'availability': {
        'weekly': {
          for (final e in avail.minutesByWeekday.entries) '${e.key}': e.value,
        },
        'overrides': avail.overrides,
        'busy': [
          for (final b in avail.busy)
            {
              'id': b.id,
              'label': b.label,
              'start': b.startMinute,
              'end': b.endMinute,
              'weekday': b.weekday,
              'date': d(b.date),
            },
        ],
      },
      'settings': settings,
    });
  }

  /// Writes an export to a real file on shared storage and returns its path.
  ///
  /// `/sdcard/Download/Prahar/` on Android — accessible from the file manager
  /// or when the phone is connected. Path is Android-shaped by design, but
  /// falls back to the app's temp dir on other platforms.
  Future<String> exportToFile() async {
    final dir = Platform.isAndroid
        ? Directory('/sdcard/Download/Prahar')
        : Directory.systemTemp;
    await dir.create(recursive: true);
    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final path = p.join(dir.path, 'prahar-backup-$stamp.json');
    await File(path).writeAsString(await serialise(), flush: true);
    return path;
  }

  /// Applies a serialised backup, replacing everything currently in the local
  /// database.
  ///
  /// Deletes-then-inserts rather than merge: two devices might both use a
  /// topic id "t3" for different topics, and reconciling that automatically is
  /// worse than the user's expectation of "restore my export exactly as it
  /// was". The caller must confirm this.
  Future<ImportReport> import(String json) async {
    final root = jsonDecode(json) as Map<String, Object?>;
    final format = (root['format'] as num?)?.toInt() ?? 0;
    if (format < 1 || format > _formatVersion) {
      throw StateError(
        'Backup format $format is not supported by this version of Prahar.',
      );
    }

    DateTime? parse(Object? v) =>
        v is String && v.isNotEmpty ? parseDateKey(v) : null;

    // Read everything first so a malformed payload throws before we touch the
    // database. Half-restored is worse than not restored.
    final subjects = <Subject>[
      for (final s in (root['subjects'] as List? ?? const []).cast<Map>())
        Subject(
          id: s['id'] as String,
          name: s['name'] as String,
          examDate: parse(s['exam_date']),
          weight: (s['weight'] as num).toInt(),
          colorValue: (s['color'] as num).toInt(),
        ),
    ];
    final topics = <Topic>[
      for (final t in (root['topics'] as List? ?? const []).cast<Map>())
        Topic(
          id: t['id'] as String,
          subjectId: t['subject_id'] as String,
          title: t['title'] as String,
          estimatedMinutes: (t['estimated_minutes'] as num).toInt(),
          completedMinutes: (t['completed_minutes'] as num?)?.toInt() ?? 0,
          difficulty: (t['difficulty'] as num?)?.toInt() ?? 3,
          prerequisiteIds:
              (t['prerequisite_ids'] as List? ?? const []).cast<String>(),
          status: TopicStatus.values.firstWhere(
            (v) => v.name == t['status'],
            orElse: () => TopicStatus.notStarted,
          ),
          firstCompletedOn: parse(t['first_completed_on']),
          estimateUnit: EffortUnit.values.firstWhere(
            (v) => v.name == t['estimate_unit'],
            orElse: () => EffortUnit.minutes,
          ),
          estimateAmount:
              (t['estimate_amount'] as num?)?.toInt() ?? (t['estimated_minutes'] as num).toInt(),
          estimateRate: (t['estimate_rate'] as num?)?.toDouble() ?? 1.0,
          link: t['link'] as String?,
        ),
    ];

    final availRaw = root['availability'] as Map? ?? const {};
    final weekly = <int, int>{
      for (final e in ((availRaw['weekly'] as Map?) ?? const {}).entries)
        int.parse(e.key as String): (e.value as num).toInt(),
    };
    final overrides = <String, int>{
      for (final e in ((availRaw['overrides'] as Map?) ?? const {}).entries)
        e.key as String: (e.value as num).toInt(),
    };
    final busy = <BusySlot>[
      for (final b in ((availRaw['busy'] as List?) ?? const []).cast<Map>())
        BusySlot(
          id: b['id'] as String,
          label: b['label'] as String,
          startMinute: (b['start'] as num).toInt(),
          endMinute: (b['end'] as num).toInt(),
          weekday: (b['weekday'] as num?)?.toInt(),
          date: parse(b['date']),
        ),
    ];
    final settings = <String, String>{
      for (final e in ((root['settings'] as Map?) ?? const {}).entries)
        e.key as String: '${e.value}',
    };

    // Now write. Delete children first so the cascade is deterministic.
    await db.clearAll();
    for (final s in subjects) { await db.upsertSubject(s); }
    for (final t in topics) { await db.upsertTopic(t); }
    await db.saveAvailability(
      Availability(minutesByWeekday: weekly, overrides: overrides, busy: []),
    );
    for (final b in busy) { await db.upsertBusySlot(b); }
    for (final e in settings.entries) {
      await db.putSetting(e.key, e.value);
    }

    return ImportReport(subjects.length, topics.length, busy.length);
  }
}

class ImportReport {
  final int subjects;
  final int topics;
  final int busy;
  const ImportReport(this.subjects, this.topics, this.busy);

  @override
  String toString() =>
      'Restored $subjects subjects, $topics topics, $busy busy slots.';
}
