import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../domain/models.dart';
import '../domain/schedule.dart';

/// Local SQLite store. No server, no account, no network.
///
/// Note what is *not* stored here: the schedule itself. Sessions are derived
/// output — regenerated from topics + availability every time anything changes.
/// Persisting them would mean two sources of truth that drift apart the first
/// time a student edits a topic.
///
/// What *is* persisted is what actually happened ([logSession]), because that
/// can never be recomputed.
class PraharDatabase {
  static const _fileName = 'prahar.db';

  /// 1 -> 2 recorded how an estimate was entered (unit, amount, rate) and added
  /// the settings table for the study window.
  ///
  /// 2 -> 3 added the busy_slots table. It had been slipped into the _v2
  /// migration after that version had already shipped, so on any device
  /// upgraded through v2 the table was missing and every save threw silently.
  /// The lesson is written in blood: once a version has run on a real device,
  /// editing that version's code does nothing. Every schema change gets its
  /// own version, always.
  ///
  /// 3 -> 4 added the `link` column on topics.
  ///
  /// 4 -> 5 added `exam_minute` on subjects — what time the exam starts, so
  /// the exam day stops counting as a whole day of preparation.
  static const _version = 5;

  late final Database _db;

  Future<void> open({String? path}) async {
    final dir = path ?? await getDatabasesPath();
    _db = await openDatabase(
      p.join(dir, _fileName),
      version: _version,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        await _create(db, version);
        await _v2(db);
        await _v3(db);
        await _v4(db);
        await _v5(db);
      },
      onUpgrade: _upgrade,
    );
  }

  /// Migrations run once, on real data, with no second chance — so each step is
  /// additive and backfills rather than rewriting. Each version's function
  /// is also idempotent (CREATE IF NOT EXISTS, ADD COLUMN guarded by
  /// PRAGMA table_info) so a redundant call cannot break an install.
  Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) await _v2(db);
    if (from < 3) await _v3(db);
    if (from < 4) await _v4(db);
    if (from < 5) await _v5(db);
  }

  Future<void> _v2(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(topics)');
    final has = cols.map((c) => c['name'] as String).toSet();

    // SQLite permits ADD COLUMN ... NOT NULL only with a DEFAULT.
    if (!has.contains('estimate_unit')) {
      await db.execute(
        "ALTER TABLE topics ADD COLUMN estimate_unit TEXT NOT NULL DEFAULT 'minutes'",
      );
    }
    if (!has.contains('estimate_amount')) {
      await db.execute('ALTER TABLE topics ADD COLUMN estimate_amount INTEGER');
    }
    if (!has.contains('estimate_rate')) {
      await db.execute('ALTER TABLE topics ADD COLUMN estimate_rate REAL');
    }

    // Existing rows were entered in minutes, which is exactly what they were.
    await db.execute('''
      UPDATE topics
         SET estimate_amount = COALESCE(estimate_amount, estimated_minutes),
             estimate_rate   = COALESCE(estimate_rate, 1.0)
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )''');
  }

  Future<void> _v3(Database db) async {
    // Belongs in its own version so devices already at v2 pick this up.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS busy_slots (
        id            TEXT PRIMARY KEY,
        label         TEXT    NOT NULL,
        start_minute  INTEGER NOT NULL,
        end_minute    INTEGER NOT NULL,
        weekday       INTEGER,
        one_off_date  TEXT
      )''');
  }

  Future<void> _v4(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(topics)');
    final has = cols.map((c) => c['name'] as String).toSet();
    if (!has.contains('link')) {
      await db.execute('ALTER TABLE topics ADD COLUMN link TEXT');
    }
  }

  /// The exam's time of day, in minutes from midnight. Nullable and left null
  /// on every existing row: "date known, time unknown" is the honest reading
  /// of a subject entered before this column existed, and it is also the
  /// behaviour those subjects already had.
  Future<void> _v5(Database db) async {
    final cols = await db.rawQuery('PRAGMA table_info(subjects)');
    final has = cols.map((c) => c['name'] as String).toSet();
    if (!has.contains('exam_minute')) {
      await db.execute('ALTER TABLE subjects ADD COLUMN exam_minute INTEGER');
    }
  }

  // ----------------------------------------------------------- busy slots

  Future<List<BusySlot>> busySlots() async {
    final rows = await _db.query('busy_slots', orderBy: 'start_minute');
    return [
      for (final r in rows)
        BusySlot(
          id: r['id'] as String,
          label: r['label'] as String,
          startMinute: r['start_minute'] as int,
          endMinute: r['end_minute'] as int,
          weekday: r['weekday'] as int?,
          date: r['one_off_date'] == null
              ? null
              : parseDateKey(r['one_off_date'] as String),
        ),
    ];
  }

  Future<void> upsertBusySlot(BusySlot s) => _upsert('busy_slots', {
    'id': s.id,
    'label': s.label,
    'start_minute': s.startMinute,
    'end_minute': s.endMinute,
    'weekday': s.weekday,
    'one_off_date': s.date == null ? null : dateKey(s.date!),
  });

  Future<void> deleteBusySlot(String id) =>
      _db.delete('busy_slots', where: 'id = ?', whereArgs: [id]);

  /// Empties every user-owned table. Used only by the backup importer so an
  /// import lands as an exact replacement rather than a merge whose id
  /// collisions would produce something the user did not export.
  Future<void> clearAll() async {
    final b = _db.batch();
    // Order does not matter thanks to foreign_keys=ON + CASCADE, but topics
    // and resources go first to make the sqlite journal smaller.
    b.delete('resources');
    b.delete('session_log');
    b.delete('topics');
    b.delete('subjects');
    b.delete('busy_slots');
    b.delete('availability_overrides');
    b.delete('settings');
    await b.commit(noResult: true);
  }

  // ------------------------------------------------------------- settings

  Future<Map<String, String>> settings() async {
    final rows = await _db.query('settings');
    return {for (final r in rows) r['key'] as String: r['value'] as String};
  }

  Future<void> putSetting(String key, String value) =>
      _upsertKeyed('settings', 'key', {'key': key, 'value': value});

  Future<void> _upsertKeyed(
    String table,
    String keyColumn,
    Map<String, Object?> values,
  ) async {
    final updated = await _db.update(
      table,
      values,
      where: '$keyColumn = ?',
      whereArgs: [values[keyColumn]],
    );
    if (updated == 0) await _db.insert(table, values);
  }

  Future<void> close() => _db.close();

  Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE subjects (
        id         TEXT PRIMARY KEY,
        name       TEXT    NOT NULL,
        exam_date  TEXT,
        weight     INTEGER NOT NULL DEFAULT 3,
        color      INTEGER NOT NULL
      )''');

    await db.execute('''
      CREATE TABLE topics (
        id                 TEXT PRIMARY KEY,
        subject_id         TEXT    NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
        title              TEXT    NOT NULL,
        estimated_minutes  INTEGER NOT NULL,
        completed_minutes  INTEGER NOT NULL DEFAULT 0,
        difficulty         INTEGER NOT NULL DEFAULT 3,
        prerequisite_ids   TEXT    NOT NULL DEFAULT '',
        status             TEXT    NOT NULL DEFAULT 'notStarted',
        first_completed_on TEXT,
        sort_order         INTEGER NOT NULL DEFAULT 0
      )''');

    await db.execute('''
      CREATE TABLE resources (
        id               TEXT PRIMARY KEY,
        topic_id         TEXT    NOT NULL REFERENCES topics(id) ON DELETE CASCADE,
        kind             TEXT    NOT NULL,
        title            TEXT    NOT NULL,
        locator          TEXT,
        page_start       INTEGER,
        page_end         INTEGER,
        duration_seconds INTEGER,
        problem_count    INTEGER,
        completed_units  INTEGER NOT NULL DEFAULT 0
      )''');

    await db.execute('''
      CREATE TABLE availability (
        weekday INTEGER PRIMARY KEY,
        minutes INTEGER NOT NULL
      )''');

    await db.execute('''
      CREATE TABLE availability_overrides (
        day     TEXT PRIMARY KEY,
        minutes INTEGER NOT NULL
      )''');

    // The audit trail: planned vs actual, which also feeds effort calibration.
    await db.execute('''
      CREATE TABLE session_log (
        id              TEXT PRIMARY KEY,
        topic_id        TEXT NOT NULL,
        subject_id      TEXT NOT NULL,
        topic_title     TEXT NOT NULL DEFAULT '',
        subject_name    TEXT NOT NULL DEFAULT '',
        day             TEXT NOT NULL,
        planned_minutes INTEGER NOT NULL,
        actual_minutes  INTEGER NOT NULL,
        kind            TEXT NOT NULL,
        status          TEXT NOT NULL
      )''');

    await db.execute('CREATE INDEX idx_topics_subject ON topics(subject_id)');
    await db.execute('CREATE INDEX idx_resources_topic ON resources(topic_id)');
    await db.execute('CREATE INDEX idx_log_day ON session_log(day)');

    final batch = db.batch();
    final standard = Availability.standard();
    for (final e in standard.minutesByWeekday.entries) {
      batch.insert('availability', {'weekday': e.key, 'minutes': e.value});
    }
    await batch.commit(noResult: true);
  }

  /// Insert-or-update a row **without** `INSERT OR REPLACE`.
  ///
  /// `ConflictAlgorithm.replace` compiles to `INSERT OR REPLACE`, which does
  /// not update in place: it DELETEs the conflicting row and inserts a new one.
  /// With `PRAGMA foreign_keys = ON` (set in [_create]'s onConfigure) that
  /// delete fires `ON DELETE CASCADE` on children — so saving an edited subject
  /// silently destroyed every topic beneath it, and saving an edited topic
  /// destroyed its resources.
  ///
  /// The damage is invisible at the call site and total, which is why this
  /// helper exists and why no write in this class may use `replace` on a table
  /// that has children.
  Future<void> _upsert(String table, Map<String, Object?> values) async {
    final updated = await _db.update(
      table,
      values,
      where: 'id = ?',
      whereArgs: [values['id']],
    );
    if (updated == 0) await _db.insert(table, values);
  }

  // ------------------------------------------------------------- subjects

  Future<List<Subject>> subjects() async {
    final rows = await _db.query('subjects', orderBy: 'name');
    return rows.map(_subjectFrom).toList();
  }

  Future<void> upsertSubject(Subject s) => _upsert('subjects', {
    'id': s.id,
    'name': s.name,
    'exam_date': s.examDate == null ? null : dateKey(s.examDate!),
    'exam_minute': s.examMinuteOfDay,
    'weight': s.weight,
    'color': s.colorValue,
  });

  Future<void> deleteSubject(String id) =>
      _db.delete('subjects', where: 'id = ?', whereArgs: [id]);

  Subject _subjectFrom(Map<String, Object?> r) => Subject(
    id: r['id'] as String,
    name: r['name'] as String,
    examDate: r['exam_date'] == null
        ? null
        : parseDateKey(r['exam_date'] as String),
    examMinuteOfDay: r['exam_minute'] as int?,
    weight: r['weight'] as int,
    colorValue: r['color'] as int,
  );

  // --------------------------------------------------------------- topics

  Future<List<Topic>> topics() async {
    final rows = await _db.query('topics', orderBy: 'sort_order, title');
    return rows.map(_topicFrom).toList();
  }

  Future<List<Topic>> topicsFor(String subjectId) async {
    final rows = await _db.query(
      'topics',
      where: 'subject_id = ?',
      whereArgs: [subjectId],
      orderBy: 'sort_order, title',
    );
    return rows.map(_topicFrom).toList();
  }

  Future<void> upsertTopic(Topic t, {int sortOrder = 0}) => _upsert('topics', {
    'id': t.id,
    'subject_id': t.subjectId,
    'title': t.title,
    'estimated_minutes': t.estimatedMinutes,
    'completed_minutes': t.completedMinutes,
    'difficulty': t.difficulty,
    'prerequisite_ids': t.prerequisiteIds.join(','),
    'status': t.status.name,
    'first_completed_on': t.firstCompletedOn == null
        ? null
        : dateKey(t.firstCompletedOn!),
    'sort_order': sortOrder,
    'estimate_unit': t.estimateUnit.name,
    'estimate_amount': t.estimateAmount,
    'estimate_rate': t.estimateRate,
    'link': t.link,
  });

  Future<void> deleteTopic(String id) =>
      _db.delete('topics', where: 'id = ?', whereArgs: [id]);

  Topic _topicFrom(Map<String, Object?> r) {
    final raw = (r['prerequisite_ids'] as String?) ?? '';
    return Topic(
      id: r['id'] as String,
      subjectId: r['subject_id'] as String,
      title: r['title'] as String,
      estimatedMinutes: r['estimated_minutes'] as int,
      completedMinutes: r['completed_minutes'] as int,
      difficulty: r['difficulty'] as int,
      prerequisiteIds: raw.isEmpty
          ? const []
          : raw.split(',').where((s) => s.isNotEmpty).toList(),
      status: TopicStatus.values.firstWhere(
        (v) => v.name == r['status'],
        orElse: () => TopicStatus.notStarted,
      ),
      firstCompletedOn: r['first_completed_on'] == null
          ? null
          : parseDateKey(r['first_completed_on'] as String),
      estimateUnit: EffortUnit.values.firstWhere(
        (v) => v.name == r['estimate_unit'],
        orElse: () => EffortUnit.minutes,
      ),
      // Null for rows written before v2, and for any row the migration could
      // not backfill; falling back to the minutes figure is always truthful.
      estimateAmount:
          (r['estimate_amount'] as int?) ?? (r['estimated_minutes'] as int),
      estimateRate: (r['estimate_rate'] as num?)?.toDouble() ?? 1.0,
      link: r['link'] as String?,
    );
  }

  // ------------------------------------------------------------ resources

  Future<List<Resource>> resourcesFor(String topicId) async {
    final rows = await _db.query(
      'resources',
      where: 'topic_id = ?',
      whereArgs: [topicId],
    );
    return rows.map(_resourceFrom).toList();
  }

  Future<void> upsertResource(Resource r) => _upsert('resources', {
    'id': r.id,
    'topic_id': r.topicId,
    'kind': r.kind.name,
    'title': r.title,
    'locator': r.locator,
    'page_start': r.pageStart,
    'page_end': r.pageEnd,
    'duration_seconds': r.durationSeconds,
    'problem_count': r.problemCount,
    'completed_units': r.completedUnits,
  });

  Future<void> deleteResource(String id) =>
      _db.delete('resources', where: 'id = ?', whereArgs: [id]);

  Resource _resourceFrom(Map<String, Object?> r) => Resource(
    id: r['id'] as String,
    topicId: r['topic_id'] as String,
    kind: ResourceKind.values.firstWhere(
      (v) => v.name == r['kind'],
      orElse: () => ResourceKind.url,
    ),
    title: r['title'] as String,
    locator: r['locator'] as String?,
    pageStart: r['page_start'] as int?,
    pageEnd: r['page_end'] as int?,
    durationSeconds: r['duration_seconds'] as int?,
    problemCount: r['problem_count'] as int?,
    completedUnits: r['completed_units'] as int,
  );

  // --------------------------------------------------------- availability

  Future<Availability> availability() async {
    final weekly = await _db.query('availability');
    final overrides = await _db.query('availability_overrides');
    // busy_slots was added in v2; on a v1 database it does not exist yet, so
    // read defensively rather than assuming schema alignment.
    List<BusySlot> slots = const [];
    try {
      slots = await busySlots();
    } catch (_) {}
    return Availability(
      minutesByWeekday: {
        for (final r in weekly) r['weekday'] as int: r['minutes'] as int,
      },
      overrides: {
        for (final r in overrides) r['day'] as String: r['minutes'] as int,
      },
      busy: slots,
    );
  }

  Future<void> saveAvailability(Availability a) async {
    final batch = _db.batch();
    for (final e in a.minutesByWeekday.entries) {
      batch.insert('availability', {
        'weekday': e.key,
        'minutes': e.value,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    batch.delete('availability_overrides');
    for (final e in a.overrides.entries) {
      batch.insert('availability_overrides', {
        'day': e.key,
        'minutes': e.value,
      });
    }
    await batch.commit(noResult: true);
  }

  // ------------------------------------------------------------------ log

  Future<void> logSession(StudySession session, {required int actualMinutes}) =>
      _upsert('session_log', {
        'id': session.id,
        'topic_id': session.topicId,
        'subject_id': session.subjectId,
        'topic_title': session.topicTitle,
        'subject_name': session.subjectName,
        'day': dateKey(session.date),
        'planned_minutes': session.durationMinutes,
        'actual_minutes': actualMinutes,
        'kind': session.kind.name,
        'status': session.status.name,
      });

  Future<void> deleteLogEntry(String id) =>
      _db.delete('session_log', where: 'id = ?', whereArgs: [id]);

  /// Everything ever logged against a subject.
  ///
  /// `session_log` deliberately carries no foreign key — it is an audit trail
  /// and outlives the topic it describes, which is what lets a finished topic
  /// be edited without losing its history. The cost is that deleting a subject
  /// does *not* cascade here, so a deleted subject went on appearing in
  /// today's log and counting towards the streak. Deleting a subject is a
  /// statement that it should be gone; this is the other half of it.
  Future<void> deleteLogForSubject(String subjectId) => _db.delete(
    'session_log',
    where: 'subject_id = ?',
    whereArgs: [subjectId],
  );

  /// Every completed session ever logged for [topicIds]. Used by the
  /// calibration pass, which asks "given how long this student actually took
  /// on these topics, what's their real reading rate for their subject".
  Future<List<LoggedSession>> completedFor(Iterable<String> topicIds) async {
    if (topicIds.isEmpty) return const [];
    final placeholders = List.filled(topicIds.length, '?').join(',');
    final rows = await _db.query(
      'session_log',
      where:
          "topic_id IN ($placeholders) AND status = 'done' "
          "AND kind = 'newMaterial' AND actual_minutes > 0",
      whereArgs: topicIds.toList(),
      orderBy: 'day',
    );
    return rows.map(_logFrom).toList();
  }

  /// The whole audit trail, oldest first.
  ///
  /// Only the backup needs this. Everything else in the app asks the log a
  /// narrow question — this day, these topics — because the log grows without
  /// bound and no screen wants all of it.
  Future<List<LoggedSession>> allLogEntries() async {
    final rows = await _db.query('session_log', orderBy: 'day, rowid');
    return rows.map(_logFrom).toList();
  }

  /// Puts a logged session back, exactly as it was.
  ///
  /// Distinct from [logSession], which takes a live StudySession and records
  /// what just happened to it. A restore has no session to speak of — the
  /// block it describes was regenerated out of existence long ago — so it
  /// writes the row directly.
  Future<void> restoreLogEntry(LoggedSession e) => _upsert('session_log', {
    'id': e.id,
    'topic_id': e.topicId,
    'subject_id': e.subjectId,
    'topic_title': e.topicTitle,
    'subject_name': e.subjectName,
    'day': dateKey(e.day),
    'planned_minutes': e.plannedMinutes,
    'actual_minutes': e.actualMinutes,
    'kind': e.kind.name,
    'status': e.status.name,
  });

  /// Everything logged on [day], newest last.
  Future<List<LoggedSession>> logEntriesOn(DateTime day) async {
    final rows = await _db.query(
      'session_log',
      where: 'day = ?',
      whereArgs: [dateKey(day)],
      orderBy: 'rowid',
    );
    return rows.map(_logFrom).toList();
  }

  LoggedSession _logFrom(Map<String, Object?> r) => LoggedSession(
    id: r['id'] as String,
    topicId: r['topic_id'] as String,
    subjectId: r['subject_id'] as String,
    topicTitle: (r['topic_title'] as String?) ?? '',
    subjectName: (r['subject_name'] as String?) ?? '',
    day: parseDateKey(r['day'] as String),
    plannedMinutes: r['planned_minutes'] as int,
    actualMinutes: r['actual_minutes'] as int,
    kind: SessionKind.values.firstWhere(
      (v) => v.name == r['kind'],
      orElse: () => SessionKind.newMaterial,
    ),
    status: SessionStatus.values.firstWhere(
      (v) => v.name == r['status'],
      orElse: () => SessionStatus.done,
    ),
  );

  Future<int> minutesStudiedOn(DateTime day) async {
    final rows = await _db.rawQuery(
      "SELECT SUM(actual_minutes) AS m FROM session_log "
      "WHERE day = ? AND status = 'done'",
      [dateKey(day)],
    );
    return (rows.first['m'] as int?) ?? 0;
  }

  /// Consecutive days with at least one completed session, counting back from
  /// [from]. Cheap streak counter — students respond to it more than to any
  /// analytics chart.
  Future<int> streakEndingAt(DateTime from) async {
    final rows = await _db.rawQuery(
      "SELECT DISTINCT day FROM session_log WHERE status = 'done' "
      "ORDER BY day DESC",
    );
    final days = rows.map((r) => r['day'] as String).toSet();
    var streak = 0;
    for (var d = dateOnly(from); ; d = d.subtract(const Duration(days: 1))) {
      if (!days.contains(dateKey(d))) break;
      streak++;
    }
    return streak;
  }
}
