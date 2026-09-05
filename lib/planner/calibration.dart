import '../domain/models.dart';
import '../domain/schedule.dart';
import 'estimator.dart';

/// One recommendation the app can make: "your Chemistry pages take longer
/// than we estimated — update 12 topics to 4.5 min/page?".
///
/// Deliberately per-subject rather than per-topic. A student reads Organic
/// Chemistry at one speed and Maths at another; per-topic recommendations
/// would starve on evidence (few topics get enough sessions to be significant)
/// and drown the user in individual prompts.
class CalibrationSuggestion {
  final String subjectId;
  final EffortUnit unit;

  /// Rate the student's topics are currently estimated at (the prior).
  final double currentRate;

  /// Rate the log-derived samples recommend.
  final double recommendedRate;

  /// How many completed blocks fed the recommendation.
  final int sampleCount;

  /// Topics that will actually change if applied.
  ///
  /// A topic with `estimateUnit == minutes` was entered in minutes and has no
  /// rate to recalibrate; a topic already at the recommended rate is skipped.
  final List<String> affectedTopicIds;

  const CalibrationSuggestion({
    required this.subjectId,
    required this.unit,
    required this.currentRate,
    required this.recommendedRate,
    required this.sampleCount,
    required this.affectedTopicIds,
  });

  double get relativeChange => (recommendedRate - currentRate) / currentRate;

  bool get isFaster => recommendedRate < currentRate;
}

/// Turns finished topics into calibration samples.
///
/// Only *completed* topics count. An in-progress topic is tempting evidence —
/// "the student spent 30 min on this 40-page chapter" — but there is no
/// honest way to know how many pages the session covered without asking, and
/// prorating by minutes cancels out arithmetically (the derived rate always
/// equals the prior). A finished topic is the one case where the two ends of
/// the ratio are both known: `amount` units, `totalActualMinutes` spent.
class Calibrator {
  const Calibrator();

  /// Groups topics by (subjectId, estimateUnit) and produces at most one
  /// suggestion per group. Topics without countable units (Minutes) or
  /// without any logged time are skipped.
  List<CalibrationSuggestion> analyse({
    required List<Topic> topics,
    required List<LoggedSession> completed,
  }) {
    final minutesByTopic = <String, int>{};
    for (final s in completed) {
      minutesByTopic.update(
        s.topicId,
        (v) => v + s.actualMinutes,
        ifAbsent: () => s.actualMinutes,
      );
    }

    final byGroup = <_GroupKey, _GroupAccum>{};
    for (final topic in topics) {
      if (topic.estimateUnit == EffortUnit.minutes) continue;
      final key = _GroupKey(topic.subjectId, topic.estimateUnit);
      final accum = byGroup.putIfAbsent(
        key,
        () => _GroupAccum(topic.estimateRate),
      );
      accum.topicIds.add(topic.id);

      // The prior rate itself becomes a shrinkage-weighted sample for every
      // topic in the group, whether finished or not. That anchors the estimate
      // when only one or two topics have completed.
      final actualMinutes = minutesByTopic[topic.id] ?? 0;
      if (!topic.isDone || actualMinutes <= 0) continue;
      accum.samples.add(
        CalibrationSample(
          units: topic.estimateAmount.toDouble(),
          actualMinutes: actualMinutes.toDouble(),
        ),
      );
    }

    final out = <CalibrationSuggestion>[];
    for (final entry in byGroup.entries) {
      final rec = EffortEstimator.recommend(
        samples: entry.value.samples,
        priorRate: entry.value.priorRate,
      );
      if (rec == null) continue;

      // Only recommend for topics that would actually change and still have
      // remaining work — no point rewriting a completed topic's estimate.
      final affected = <String>[];
      for (final id in entry.value.topicIds) {
        final t = topics.firstWhere((t) => t.id == id);
        if (t.isDone) continue;
        if ((t.estimateRate - rec.rate).abs() < 0.05) continue;
        affected.add(id);
      }
      if (affected.isEmpty) continue;

      out.add(
        CalibrationSuggestion(
          subjectId: entry.key.subjectId,
          unit: entry.key.unit,
          currentRate: entry.value.priorRate,
          recommendedRate: rec.rate,
          sampleCount: rec.samples,
          affectedTopicIds: affected,
        ),
      );
    }
    return out;
  }
}

class _GroupKey {
  final String subjectId;
  final EffortUnit unit;
  const _GroupKey(this.subjectId, this.unit);

  @override
  bool operator ==(Object other) =>
      other is _GroupKey && other.subjectId == subjectId && other.unit == unit;

  @override
  int get hashCode => Object.hash(subjectId, unit);
}

class _GroupAccum {
  final double priorRate;
  final List<CalibrationSample> samples = [];
  final List<String> topicIds = [];
  _GroupAccum(this.priorRate);
}
