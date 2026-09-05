import '../domain/models.dart';

/// One observation of "this much material actually took this long".
class CalibrationSample {
  /// Pages read, problems solved, or seconds of video — whatever the rate is
  /// measured against.
  final double units;
  final double actualMinutes;

  const CalibrationSample({required this.units, required this.actualMinutes});
}

/// Turns countable material into minutes.
///
/// Students are famously bad at estimating time but perfectly good at counting
/// pages and reading a video's runtime. So never ask for minutes — ask for the
/// thing they can see, and convert.
///
/// The rates then get [calibrate]d per subject from logged sessions, so after
/// a couple of weeks the app knows this student reads Organic Chemistry at
/// 5 min/page and Maths at 2. That feedback loop is what makes the schedule
/// believable instead of aspirational.
class EffortEstimator {
  final double minutesPerPage;
  final double minutesPerProblem;

  /// Videos take longer than their runtime: pausing, rewinding, note-taking.
  final double videoOverhead;

  const EffortEstimator({
    this.minutesPerPage = 3.0,
    this.minutesPerProblem = 6.0,
    this.videoOverhead = 1.3,
  });

  static const defaults = EffortEstimator();

  /// Minutes per unit for [unit]. The rate is recorded on the topic so a later
  /// change here cannot retroactively rewrite existing estimates.
  double rateFor(EffortUnit unit) => switch (unit) {
    EffortUnit.minutes => 1.0,
    EffortUnit.pages => minutesPerPage,
    EffortUnit.problems => minutesPerProblem,
  };

  /// Converts a figure between units, preserving the underlying effort.
  ///
  /// Lives here rather than in the topic sheet: this is domain arithmetic, and
  /// having it in the widget was both a purity-rule violation and the source of
  /// a silent 3x inflation when the unit was switched.
  int convert(int amount, EffortUnit from, EffortUnit to) {
    if (amount <= 0 || from == to) return amount;
    final minutes = amount * rateFor(from);
    return (minutes / rateFor(to)).round().clamp(1, 1 << 30);
  }

  /// Minutes of work remaining in [resource], accounting for progress already
  /// made. Returns null when the resource carries no countable measure — a
  /// bare URL, say — so the caller can fall back to asking the student.
  int? remainingMinutes(Resource resource) {
    final total = resource.totalUnits;
    if (total == null || total <= 0) return null;
    final left = (total - resource.completedUnits).clamp(0, total);
    return _minutesForUnits(resource.kind, left);
  }

  /// Minutes for the whole resource, ignoring progress.
  int? totalMinutes(Resource resource) {
    final total = resource.totalUnits;
    if (total == null || total <= 0) return null;
    return _minutesForUnits(resource.kind, total);
  }

  int _minutesForUnits(ResourceKind kind, int units) => switch (kind) {
    ResourceKind.book || ResourceKind.pdf => (units * minutesPerPage).round(),
    ResourceKind.problemSet => (units * minutesPerProblem).round(),
    ResourceKind.video => (units / 60.0 * videoOverhead).round(),
    ResourceKind.url => 0,
  };

  /// Sum of every resource attached to a topic. Resources with no measure
  /// contribute nothing rather than blocking the estimate.
  int estimateTopic(Iterable<Resource> resources) =>
      resources.map(totalMinutes).whereType<int>().fold(0, (a, b) => a + b);

  EffortEstimator copyWith({
    double? minutesPerPage,
    double? minutesPerProblem,
    double? videoOverhead,
  }) => EffortEstimator(
    minutesPerPage: minutesPerPage ?? this.minutesPerPage,
    minutesPerProblem: minutesPerProblem ?? this.minutesPerProblem,
    videoOverhead: videoOverhead ?? this.videoOverhead,
  );

  /// Turns a per-subject observation set into a recommended rate.
  ///
  /// One observation per completed block that used real units: the count of
  /// pages (or problems, or minutes) the topic represented, and the actual
  /// minutes it took. Same shrinkage logic as [calibrate] so the recommendation
  /// is stable — three sessions nudge the rate; twenty sessions replace it.
  ///
  /// [priorRate] is the rate the topic was estimated at; the return value is
  /// blended toward it. Returns null when the observations are too few or too
  /// consistent with the prior to be worth acting on — the app should not
  /// nag when there is nothing new to learn.
  static ({double rate, int samples})? recommend({
    required List<CalibrationSample> samples,
    required double priorRate,
    int minSamples = 3,
    double threshold = 0.15,
  }) {
    if (samples.length < minSamples) return null;
    final rate = calibrate(samples: samples, prior: priorRate);
    // Only recommend if it changes the estimate by more than [threshold]
    // relative — a 5% correction is not worth interrupting anyone for.
    if ((rate - priorRate).abs() / priorRate < threshold) return null;
    return (rate: rate, samples: samples.length);
  }

  /// Blends the observed rate with [prior], shrinking toward the prior when
  /// there is little evidence.
  ///
  /// Weight on the observation is `n / (n + smoothing)`, so a single session
  /// nudges the rate rather than overwriting it, while twenty sessions almost
  /// entirely replace it. Without this, one interrupted study session would
  /// wreck every future estimate.
  static double calibrate({
    required List<CalibrationSample> samples,
    required double prior,
    double smoothing = 5,
  }) {
    if (samples.isEmpty) return prior;

    var units = 0.0;
    var minutes = 0.0;
    for (final s in samples) {
      if (s.units <= 0) continue;
      units += s.units;
      minutes += s.actualMinutes;
    }
    if (units <= 0) return prior;

    final observed = minutes / units;
    final n = samples.length.toDouble();
    final weight = n / (n + smoothing);
    return prior * (1 - weight) + observed * weight;
  }
}
