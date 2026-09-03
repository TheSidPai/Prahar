import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/domain/models.dart';
import 'package:prahar/domain/schedule.dart';
import 'package:prahar/planner/calibration.dart';

/// Calibration is quietly the feature that makes the planner get better with
/// use, so its edges matter more than most. These pin the behaviour the app
/// is expected to *not* have — nagging on little evidence, moving estimates
/// under someone half-finished, mixing units.
void main() {
  const cal = Calibrator();

  Topic topic({
    required String id,
    required String subjectId,
    required EffortUnit unit,
    required int amount,
    required double rate,
    int completed = 0,
    TopicStatus status = TopicStatus.notStarted,
  }) =>
      Topic.fromEstimate(
        id: id,
        subjectId: subjectId,
        title: id,
        unit: unit,
        amount: amount,
        rate: rate,
        completedMinutes: completed,
        status: status,
      );

  LoggedSession session(String topicId, int minutes,
          {String subjectId = 'phys'}) =>
      LoggedSession(
        id: 'log-$topicId-$minutes',
        topicId: topicId,
        subjectId: subjectId,
        topicTitle: '',
        subjectName: '',
        day: DateTime(2026, 9, 1),
        plannedMinutes: minutes,
        actualMinutes: minutes,
        kind: SessionKind.newMaterial,
        status: SessionStatus.done,
      );

  /// Convenience: build [n] completed topics and their finish logs.
  ({List<Topic> topics, List<LoggedSession> logs}) finished({
    required String prefix,
    required String subjectId,
    required EffortUnit unit,
    required int amount,
    required double rate,
    required int actualMinutesEach,
    required int n,
  }) {
    final topics = <Topic>[];
    final logs = <LoggedSession>[];
    for (var i = 0; i < n; i++) {
      final id = '$prefix$i';
      topics.add(topic(
        id: id,
        subjectId: subjectId,
        unit: unit,
        amount: amount,
        rate: rate,
        completed: actualMinutesEach,
        status: TopicStatus.done,
      ));
      logs.add(session(id, actualMinutesEach, subjectId: subjectId));
    }
    return (topics: topics, logs: logs);
  }

  group('discipline', () {
    test('does not suggest with too little evidence', () {
      // One finished topic, huge miss — should not fire (below minSamples).
      final r = finished(
          prefix: 't', subjectId: 'phys', unit: EffortUnit.pages,
          amount: 100, rate: 3.0, actualMinutesEach: 600, n: 1);
      expect(cal.analyse(topics: r.topics, completed: r.logs), isEmpty);
    });

    test('does not suggest for a small correction', () {
      // Actual ~3.3 min/page vs prior 3.0 — a 10% drift, below the 15%
      // relevance threshold. Nudging for this is noise.
      final r = finished(
          prefix: 't', subjectId: 'phys', unit: EffortUnit.pages,
          amount: 40, rate: 3.0, actualMinutesEach: 132, n: 5);
      expect(cal.analyse(topics: r.topics, completed: r.logs), isEmpty);
    });

    test('skips minute-entered topics — no rate to recalibrate', () {
      final r = finished(
          prefix: 't', subjectId: 'phys', unit: EffortUnit.minutes,
          amount: 60, rate: 1.0, actualMinutesEach: 90, n: 5);
      expect(cal.analyse(topics: r.topics, completed: r.logs), isEmpty);
    });

    test('ignores in-progress topics — cannot compare partial work honestly',
        () {
      // Enough would-be evidence to fire, but nothing is finished, so nothing
      // may be inferred.
      final topics = [
        for (var i = 0; i < 6; i++)
          topic(
              id: 't$i', subjectId: 'phys', unit: EffortUnit.pages,
              amount: 30, rate: 3.0, completed: 90, status: TopicStatus.inProgress),
      ];
      final logs = [for (var i = 0; i < 6; i++) session('t$i', 90)];
      expect(cal.analyse(topics: topics, completed: logs), isEmpty);
    });
  });

  group('genuine signal', () {
    test('recommends a rate when finished topics prove a real difference',
        () {
      // Six 30-page topics estimated at 3 min/page (90 min each) but finished
      // in 180 minutes — real rate 6.0 min/page. Plus one open topic so the
      // recommendation has somewhere to apply; the calibrator drops
      // suggestions with an empty affected list.
      final r = finished(
          prefix: 't', subjectId: 'phys', unit: EffortUnit.pages,
          amount: 30, rate: 3.0, actualMinutesEach: 180, n: 6);
      final open = topic(
          id: 'open', subjectId: 'phys', unit: EffortUnit.pages,
          amount: 40, rate: 3.0);
      final s = cal
          .analyse(topics: [...r.topics, open], completed: r.logs)
          .single;
      expect(s.subjectId, 'phys');
      expect(s.unit, EffortUnit.pages);
      expect(s.recommendedRate, greaterThan(4.5),
          reason: 'six clear over-runs should move the rate substantially');
      expect(s.recommendedRate, lessThanOrEqualTo(6.0));
      expect(s.sampleCount, 6);
      // Completed topics are not on the affected list — their schedule is
      // already served.
      expect(s.affectedTopicIds, ['open']);
    });

    test('applies to remaining topics only, not the ones the evidence came from',
        () {
      // Six finished topics as evidence, plus three still-open topics that
      // should have their rate corrected.
      final past = finished(
          prefix: 'past', subjectId: 'phys', unit: EffortUnit.pages,
          amount: 30, rate: 3.0, actualMinutesEach: 180, n: 6);
      final open = [
        for (var i = 0; i < 3; i++)
          topic(
              id: 'open$i', subjectId: 'phys', unit: EffortUnit.pages,
              amount: 40, rate: 3.0),
      ];
      final s = cal.analyse(
        topics: [...past.topics, ...open],
        completed: past.logs,
      ).single;
      expect(s.affectedTopicIds.toSet(),
          {'open0', 'open1', 'open2'});
    });
  });

  group('grouping', () {
    test('recommends per (subject, unit) — never mixes them', () {
      final pages = finished(
          prefix: 'p', subjectId: 'phys', unit: EffortUnit.pages,
          amount: 30, rate: 3.0, actualMinutesEach: 180, n: 6);
      final problems = finished(
          prefix: 'q', subjectId: 'phys', unit: EffortUnit.problems,
          amount: 20, rate: 6.0, actualMinutesEach: 60, n: 6);
      // Add open topics in each group so the recommendation has somewhere to
      // apply, otherwise both would produce empty affected lists and drop.
      final openPages = [
        for (var i = 0; i < 2; i++)
          topic(
              id: 'openP$i', subjectId: 'phys', unit: EffortUnit.pages,
              amount: 30, rate: 3.0),
      ];
      final openProblems = [
        for (var i = 0; i < 2; i++)
          topic(
              id: 'openQ$i', subjectId: 'phys', unit: EffortUnit.problems,
              amount: 20, rate: 6.0),
      ];
      final s = cal.analyse(
        topics: [...pages.topics, ...problems.topics, ...openPages, ...openProblems],
        completed: [...pages.logs, ...problems.logs],
      );
      expect(s, hasLength(2));
      final pagesRec = s.firstWhere((x) => x.unit == EffortUnit.pages);
      final probsRec = s.firstWhere((x) => x.unit == EffortUnit.problems);
      expect(pagesRec.affectedTopicIds.every((id) => id.startsWith('openP')),
          isTrue);
      expect(probsRec.affectedTopicIds.every((id) => id.startsWith('openQ')),
          isTrue);
    });
  });
}
