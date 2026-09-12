/// The stops on Prahar's tours, in the order they come.
///
/// Every stop moves on by Next. The student is never asked to tap the app
/// during a tour: a highlighted button that is also the thing to press next
/// reads as "press it", which is exactly what confused the first version.
enum TourStop {
  welcome,
  tabs,
  subjects,
  topics,
  today,
  planProgress,
  reminders,
  finish,
  block,
  focus,
  skip,
  done,
  laterBlocks;

  /// Stops shown on the Subjects tab. Every other stop is on Today.
  bool get onSubjectsTab => this == subjects || this == topics;
}

enum TourKind { main, firstBlock }

/// The main tour.
///
/// A [replay], from the help sheet, is for someone already set up: it folds in
/// the first block's stops when Today has a block to point at, and ends on
/// reminders instead of the Add your first subject card.
List<TourStop> mainTourStops({
  required bool replay,
  bool hasBlock = false,
  bool hasLaterBlocks = false,
}) => [
  TourStop.welcome,
  TourStop.tabs,
  TourStop.subjects,
  TourStop.topics,
  TourStop.today,
  if (replay && hasBlock)
    ...firstBlockStops(hasLaterBlocks: hasLaterBlocks).skip(1),
  TourStop.planProgress,
  TourStop.reminders,
  if (!replay) TourStop.finish,
];

/// The short tour for a student's first real block, shown once.
List<TourStop> firstBlockStops({required bool hasLaterBlocks}) => [
  TourStop.block,
  TourStop.focus,
  TourStop.skip,
  TourStop.done,
  if (hasLaterBlocks) TourStop.laterBlocks,
];
