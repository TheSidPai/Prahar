/// The stops on the first-run tour.
///
/// Which stop is showing is worked out from what the student has made so far,
/// never stored as a step number. Closing the app halfway, cancelling a sheet
/// or deleting the subject all land on the right stop with no bookkeeping, for
/// the same reason the plan is derived rather than saved. The one exception is
/// [reminders]; see [tourStepFor].
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
  addTopic,

  /// A card with a row for each thing Android needs allowed, and Continue.
  reminders,

  /// Today's main card. Read.
  today,

  /// The Plan tab, and the end of the tour. Read.
  plan;

  /// Stops with nothing to do but read, and a Next button.
  bool get isRead =>
      this == welcome ||
      this == navigation ||
      this == subject ||
      this == today ||
      this == plan;

  /// Stops that wait for a tap on something in the app.
  bool get waitsForTap =>
      this == openSubjects || this == addSubject || this == addTopic;
}

/// Which stop the tour is at, or null once it is over.
///
/// [seen] holds the read stops already tapped past. The welcome and the
/// navigation stop belong to an empty app, or to a [replay]: someone coming
/// back with a subject already made is past them.
///
/// [remindersDone] is the one input that is stored rather than derived.
/// Android reports nothing about autostart, so "reminders are set up" is not
/// something the data can answer, and finishing that stop is recorded instead.
TourStep? tourStepFor({
  required bool hasSubject,
  required bool hasTopic,
  required bool showingSubjects,
  bool remindersDone = false,
  bool replay = false,
  Set<TourStep> seen = const {},
}) {
  if (!hasSubject || replay) {
    if (!seen.contains(TourStep.welcome)) return TourStep.welcome;
    if (!seen.contains(TourStep.navigation)) return TourStep.navigation;
  }
  if (!hasTopic) {
    if (!showingSubjects) return TourStep.openSubjects;
    if (!hasSubject) return TourStep.addSubject;
    if (!seen.contains(TourStep.subject)) return TourStep.subject;
    return TourStep.addTopic;
  }
  if (!remindersDone) return TourStep.reminders;
  if (!seen.contains(TourStep.today)) return TourStep.today;
  if (!seen.contains(TourStep.plan)) return TourStep.plan;
  return null;
}
