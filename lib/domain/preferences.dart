import '../planner/planner.dart';

/// The scheduling choices a student is allowed to make.
///
/// These were hardcoded in [PlannerConfig], which meant every block landed
/// between 06:00 and 22:00 no matter the person. For anyone in class during the
/// day the schedule was simply wrong, and no amount of explaining it helps —
/// a plan you cannot follow is one you stop opening.
class Prefs {
  /// Earliest a block may start, minutes from midnight.
  final int dayStartMinute;

  /// Latest a block may end.
  final int dayEndMinute;

  /// Longest single block. Shorter suits fragmented days; longer suits
  /// uninterrupted evenings.
  final int blockMinutes;

  /// Gap between consecutive blocks.
  final int breakMinutes;

  const Prefs({
    this.dayStartMinute = 6 * 60,
    this.dayEndMinute = 22 * 60,
    this.blockMinutes = 50,
    this.breakMinutes = 10,
  });

  /// The window must be wide enough for at least one block plus a break,
  /// otherwise the planner silently schedules nothing and the day looks broken
  /// for no visible reason.
  bool get isUsable => dayEndMinute - dayStartMinute >= blockMinutes;

  int get windowMinutes => dayEndMinute - dayStartMinute;

  PlannerConfig toConfig() => PlannerConfig(
        dayStartMinute: dayStartMinute,
        dayEndMinute: dayEndMinute,
        maxSessionMinutes: blockMinutes,
        // A minimum longer than the block itself would reject every block.
        minSessionMinutes: blockMinutes >= 40 ? 20 : (blockMinutes / 2).round(),
        breakMinutes: breakMinutes,
      );

  Prefs copyWith({
    int? dayStartMinute,
    int? dayEndMinute,
    int? blockMinutes,
    int? breakMinutes,
  }) =>
      Prefs(
        dayStartMinute: dayStartMinute ?? this.dayStartMinute,
        dayEndMinute: dayEndMinute ?? this.dayEndMinute,
        blockMinutes: blockMinutes ?? this.blockMinutes,
        breakMinutes: breakMinutes ?? this.breakMinutes,
      );

  Map<String, String> toMap() => {
        'day_start': '$dayStartMinute',
        'day_end': '$dayEndMinute',
        'block_minutes': '$blockMinutes',
        'break_minutes': '$breakMinutes',
      };

  /// Tolerant of missing or malformed values: a corrupt preference should fall
  /// back to a working default, never prevent the app starting.
  factory Prefs.fromMap(Map<String, String> m) {
    int read(String key, int fallback, int lo, int hi) {
      final v = int.tryParse(m[key] ?? '');
      if (v == null) return fallback;
      return v.clamp(lo, hi);
    }

    var start = read('day_start', 6 * 60, 0, 23 * 60);
    var end = read('day_end', 22 * 60, 60, 24 * 60);
    if (end <= start) {
      // Never persist or return an inverted window.
      start = 6 * 60;
      end = 22 * 60;
    }

    return Prefs(
      dayStartMinute: start,
      dayEndMinute: end,
      blockMinutes: read('block_minutes', 50, 10, 180),
      breakMinutes: read('break_minutes', 10, 0, 60),
    );
  }
}
