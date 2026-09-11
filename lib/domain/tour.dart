/// The stops on the first-run tour.
///
/// Which stop is showing is worked out from what the student has made so far,
/// never stored as a step number. Closing the app halfway, cancelling a sheet
/// or deleting the subject all land on the right stop with no bookkeeping, for
/// the same reason the plan is derived rather than saved.
enum TourStep {
  /// A card with the mark. Read.
  welcome,

  /// The navigation, one stop for all five tabs. Read.
  navigation,

  /// Waits for Subjects to be tapped.
  openSubjects,

  /// Waits for a subject to be saved.
  addSubject,

  /// The new subject, and what its exam date does. Read.
  subject,

  /// Waits for a topic to be saved.
  addTopic;

  /// Read stops have a Next button. The others wait for the student to act.
  bool get isRead => this == welcome || this == navigation || this == subject;
}

/// Which stop the tour is at, or null once there is nothing left to set up.
///
/// [seen] holds the read stops already tapped past. The welcome and the
/// navigation stop belong to an empty app only: someone coming back with a
/// subject already made is past them, whether or not this run showed them.
TourStep? tourStepFor({
  required bool hasSubject,
  required bool hasTopic,
  required bool showingSubjects,
  Set<TourStep> seen = const {},
}) {
  if (hasTopic) return null;
  if (!hasSubject) {
    if (!seen.contains(TourStep.welcome)) return TourStep.welcome;
    if (!seen.contains(TourStep.navigation)) return TourStep.navigation;
  }
  if (!showingSubjects) return TourStep.openSubjects;
  if (!hasSubject) return TourStep.addSubject;
  if (!seen.contains(TourStep.subject)) return TourStep.subject;
  return TourStep.addTopic;
}
