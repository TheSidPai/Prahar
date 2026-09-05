import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/domain/models.dart';
import 'package:prahar/planner/estimator.dart';

Resource book(String id, {required int from, required int to, int done = 0}) =>
    Resource(
      id: id,
      topicId: 't',
      kind: ResourceKind.book,
      title: id,
      pageStart: from,
      pageEnd: to,
      completedUnits: done,
    );

void main() {
  const estimator = EffortEstimator.defaults;

  group('page counting', () {
    test('page ranges are inclusive at both ends', () {
      expect(book('b', from: 40, to: 72).pages, 33);
      expect(book('b', from: 1, to: 1).pages, 1);
    });

    test('converts pages to minutes at the configured rate', () {
      // 33 pages at 3 min/page
      expect(estimator.totalMinutes(book('b', from: 40, to: 72)), 99);
    });

    test('discounts pages already read', () {
      expect(
        estimator.remainingMinutes(book('b', from: 1, to: 100, done: 60)),
        120,
      );
    });

    test('never returns negative work when progress overshoots', () {
      expect(
        estimator.remainingMinutes(book('b', from: 1, to: 10, done: 999)),
        0,
      );
    });
  });

  group('other resource kinds', () {
    test('video runtime carries a note-taking overhead', () {
      const r = Resource(
        id: 'v',
        topicId: 't',
        kind: ResourceKind.video,
        title: 'lecture',
        durationSeconds: 3600,
      );
      // 60 minutes x 1.3
      expect(estimator.totalMinutes(r), 78);
    });

    test('problem sets price per problem', () {
      const r = Resource(
        id: 'p',
        topicId: 't',
        kind: ResourceKind.problemSet,
        title: 'exercises',
        problemCount: 20,
      );
      expect(estimator.totalMinutes(r), 120);
    });

    test('a bare URL yields no estimate rather than a wrong one', () {
      const r = Resource(
        id: 'u',
        topicId: 't',
        kind: ResourceKind.url,
        title: 'notes',
        locator: 'https://example.com',
      );
      expect(estimator.totalMinutes(r), isNull);
    });
  });

  test('a topic estimate sums its measurable resources', () {
    final resources = [
      book('b1', from: 1, to: 10), // 30
      book('b2', from: 1, to: 20), // 60
      const Resource(
        id: 'u',
        topicId: 't',
        kind: ResourceKind.url,
        title: 'link',
      ), // no measure
    ];
    expect(estimator.estimateTopic(resources), 90);
  });

  group('calibration', () {
    test('falls back to the prior with no evidence', () {
      expect(EffortEstimator.calibrate(samples: const [], prior: 3.0), 3.0);
    });

    test('one sample nudges the rate without overwriting it', () {
      // Observed 6 min/page against a prior of 3.
      final rate = EffortEstimator.calibrate(
        samples: const [CalibrationSample(units: 10, actualMinutes: 60)],
        prior: 3.0,
      );
      expect(rate, greaterThan(3.0));
      expect(rate, lessThan(4.0));
    });

    test('many samples converge on the observed rate', () {
      final samples = List.generate(
        40,
        (_) => const CalibrationSample(units: 10, actualMinutes: 60),
      );
      final rate = EffortEstimator.calibrate(samples: samples, prior: 3.0);
      expect(rate, closeTo(6.0, 0.4));
    });

    test('ignores samples with no units', () {
      final rate = EffortEstimator.calibrate(
        samples: const [CalibrationSample(units: 0, actualMinutes: 50)],
        prior: 3.0,
      );
      expect(rate, 3.0);
    });
  });
}
