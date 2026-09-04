import '../planner/planner.dart';

/// How the interface picks a colour scheme.
///
/// System is deliberately the default: a phone that switches to light in the
/// morning should carry the app with it. Explicit choices override, but are
/// not the norm.
enum ThemeChoice { system, light, dark }

/// Whether the app renders in flat "matte" surfaces or in a frosted-glass
/// language.
///
/// Deliberately narrow: two options, no gradient in between. The point of the
/// choice is a preview so the student can decide which language the app
/// speaks; a continuous slider would be a demo reel.
enum MaterialChoice { matte, glass }

/// How a card separates itself from the page behind it.
///
/// Every list in the app is made of cards, so this one choice sets the whole
/// texture of the interface. The options are five *different ideas* about
/// separation rather than five weights of the same border: an outline, a tonal
/// step, a shadow, a wash of colour, and nothing at all. Anything subtler than
/// that is a preference nobody can see.
enum CardStyle {
  /// A hairline outline on a surface-coloured fill. The original.
  hairline,

  /// No border. The fill alone is one step lighter than the page, so cards
  /// separate by tone — quieter, and it stops a long list reading as a grid.
  plain,

  /// No border, a soft diffuse shadow. Cards lift off the page.
  shadow,

  /// No border, a faint wash of the accent through the fill. Warm rather than
  /// neutral, so a card feels like part of the brand.
  tinted,

  /// No fill, no border, no shadow. Only spacing separates one thing from the
  /// next — the editorial extreme, and the least furniture on screen.
  open,
}

// There is no FontChoice any more. Seven faces were bundled behind a live
// preview so the choice could be made on how they looked rather than on their
// names; Inter won, so the picker, the enum and the six unused TTFs are gone
// and `PraharTheme.fontFamily` is the single answer. Old saved preferences may
// still carry a `font` key — it is simply ignored on read.

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

  final ThemeChoice themeChoice;
  final MaterialChoice materialChoice;
  final CardStyle cardStyle;

  /// The focus timer's last-used pattern, by `TimerMode.name`. Stored as a
  /// string rather than an enum because the modes are pairs of durations that
  /// live in `domain/study_timer.dart`; an enum here would be a second list to
  /// keep in step. Unknown values fall back to Pomodoro.
  final String timerMode;

  /// Whether the evening digest is scheduled at all, and when it fires.
  ///
  /// On by default: a planner that never speaks first is a planner you forget
  /// to open. It is a single quiet notification a day, and one switch away.
  final bool digestEnabled;

  /// Minutes from midnight. 21:00 — late enough that the day is done, early
  /// enough to still act on what it says.
  final int digestMinute;

  const Prefs({
    this.dayStartMinute = 6 * 60,
    this.dayEndMinute = 22 * 60,
    this.blockMinutes = 50,
    this.breakMinutes = 10,
    this.themeChoice = ThemeChoice.system,
    this.materialChoice = MaterialChoice.matte,
    this.cardStyle = CardStyle.hairline,
    this.timerMode = 'pomodoro',
    this.digestEnabled = true,
    this.digestMinute = 21 * 60,
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
    ThemeChoice? themeChoice,
    MaterialChoice? materialChoice,
    CardStyle? cardStyle,
    String? timerMode,
    bool? digestEnabled,
    int? digestMinute,
  }) =>
      Prefs(
        dayStartMinute: dayStartMinute ?? this.dayStartMinute,
        dayEndMinute: dayEndMinute ?? this.dayEndMinute,
        blockMinutes: blockMinutes ?? this.blockMinutes,
        breakMinutes: breakMinutes ?? this.breakMinutes,
        themeChoice: themeChoice ?? this.themeChoice,
        materialChoice: materialChoice ?? this.materialChoice,
        cardStyle: cardStyle ?? this.cardStyle,
        timerMode: timerMode ?? this.timerMode,
        digestEnabled: digestEnabled ?? this.digestEnabled,
        digestMinute: digestMinute ?? this.digestMinute,
      );

  Map<String, String> toMap() => {
        'day_start': '$dayStartMinute',
        'day_end': '$dayEndMinute',
        'block_minutes': '$blockMinutes',
        'break_minutes': '$breakMinutes',
        'theme': themeChoice.name,
        'material': materialChoice.name,
        'card_style': cardStyle.name,
        'timer_mode': timerMode,
        'digest': digestEnabled ? '1' : '0',
        'digest_minute': '$digestMinute',
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

    final theme = ThemeChoice.values.firstWhere(
      (c) => c.name == m['theme'],
      orElse: () => ThemeChoice.system,
    );
    final material = MaterialChoice.values.firstWhere(
      (c) => c.name == m['material'],
      orElse: () => MaterialChoice.matte,
    );
    final cards = CardStyle.values.firstWhere(
      (c) => c.name == m['card_style'],
      orElse: () => CardStyle.hairline,
    );

    return Prefs(
      dayStartMinute: start,
      dayEndMinute: end,
      blockMinutes: read('block_minutes', 50, 10, 180),
      breakMinutes: read('break_minutes', 10, 0, 60),
      themeChoice: theme,
      materialChoice: material,
      cardStyle: cards,
      timerMode: m['timer_mode'] ?? 'pomodoro',
      // Absent means "never set", which for a feature that ships on is on.
      digestEnabled: (m['digest'] ?? '1') != '0',
      digestMinute: read('digest_minute', 21 * 60, 0, 24 * 60 - 1),
    );
  }
}
