import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/format.dart';
import '../domain/preferences.dart';
import '../state/app_state.dart';
import 'brand.dart';
import 'busy_slots_screen.dart';
import 'glass.dart';
import 'how_it_works.dart';
import 'layout.dart';
import 'settings_screen.dart';
import 'theme.dart';

/// The Settings screen.
///
/// It shipped for a day as a sixth tab called "Look", beside the original, so
/// the two could be compared on a real device rather than argued about. That
/// comparison is over: this one won and the original is deleted. The filename
/// is a leftover of the experiment and the class is not — renaming the file is
/// a tidy-up for whenever something else touches it.
///
/// (The subpages it pushes to, the theme toggle and `savePrefs` all still live
/// in settings_screen.dart, which is now that file's whole job.)
///
/// What was wrong with the old one is not that it was ugly; it is that every
/// row was the same row. Eight identical cards, eight grey icons, eight
/// chevrons, and the only way to find anything was to read all of it. A
/// settings screen is a *map*, and a map with one symbol is a list.
///
/// Three changes carry the whole redesign:
///
///   1. **Colour means something.** Each group owns a hue and its icons are
///      tinted with it, so the eye can jump to "the amber section" without
///      reading. The palette is the app's own — indigo for structure, amber
///      for effort — extended with two more for the groups that had no
///      meaning attached.
///   2. **Appearance stops being a menu.** Theme, cards and materials are the
///      settings people actually touch, and they were three taps deep behind
///      rows that only said their current value. They are inline now, applied
///      on tap, with the result visible on the screen you are standing on.
///   3. **The top says what you have chosen.** A band carrying the mark and
///      the three current choices, so the screen opens with an answer rather
///      than a list of questions.
///
/// The theme toggle is deliberately unchanged apart from its colour: it moves
/// to the amber the nav bar uses to mark the selected tab, so "this is the one
/// you picked" is one colour everywhere in the app rather than two.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final weekTotal = List.generate(
      7,
      (i) => state.availability.minutesByWeekday[i + 1] ?? 0,
    ).fold(0, (a, b) => a + b);

    return ReadableColumn(
      child: ListView(
        padding: EdgeInsets.only(
          top: glassTopInset(context),
          bottom: navBottomInset(context),
        ),
        children: [
          // No masthead here. It moved to the Appearance page with the
          // controls it previews; leaving a copy at the top of Settings meant
          // the screen opened on a preview of a thing three rows further
          // down, and the same card appeared twice in one navigation.
          //
          // Schedule leads instead: this is a study planner, and the hours you
          // have are the setting the app is actually about.
          _GroupLabel('Schedule', colour: scheme.tertiary),
          _Tile(
            icon: Icons.schedule_rounded,
            colour: scheme.tertiary,
            title: 'Study time',
            value: '${formatMinutes(weekTotal)} a week',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const StudyTimePage()),
            ),
          ),
          _Tile(
            icon: Icons.watch_later_outlined,
            colour: scheme.tertiary,
            title: 'Study window',
            value:
                '${formatClock(state.prefs.dayStartMinute)} – '
                '${formatClock(state.prefs.dayEndMinute)} · '
                '${state.prefs.blockMinutes} min blocks',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const StudyWindowPage()),
            ),
          ),
          _Tile(
            icon: Icons.event_busy_outlined,
            colour: scheme.tertiary,
            title: 'Busy slots',
            value: state.availability.busy.isEmpty
                ? 'Nothing blocked out'
                : '${state.availability.busy.length} recorded',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const BusySlotsScreen()),
            ),
          ),

          _GroupLabel('Reminders', colour: scheme.tertiary),
          _Tile(
            icon: Icons.notifications_active_outlined,
            colour: scheme.tertiary,
            title: 'Notifications',
            // The one row in the app that is allowed to shout. A reminder that
            // will not fire is the failure this app cannot afford.
            value: state.exactAlarmsAllowed
                ? 'Exact timing allowed'
                : 'Exact alarms blocked, reminders may be late',
            warn: !state.exactAlarmsAllowed,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const RemindersPage()),
            ),
          ),

          // Appearance is a destination now, like everything else here. It was
          // inline — a toggle and two rows of chips sitting open in the list —
          // which put the least consequential settings in the most prominent
          // place and made this screen a different shape from every other row
          // on it.
          _GroupLabel('Appearance', colour: scheme.tertiary),
          _Tile(
            icon: Icons.palette_outlined,
            colour: scheme.tertiary,
            title: 'Look',
            value: [
              switch (state.prefs.themeChoice) {
                ThemeChoice.light => 'Light',
                ThemeChoice.dark => 'Dark',
                ThemeChoice.system => 'Auto',
              },
              PraharTheme.describeCards(state.prefs.cardStyle).$1,
              state.prefs.materialChoice == MaterialChoice.glass
                  ? 'Glass'
                  : 'Matte',
            ].join(' · '),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const AppearancePage()),
            ),
          ),

          _GroupLabel('Data', colour: scheme.tertiary),
          _Tile(
            icon: Icons.save_alt_rounded,
            colour: scheme.tertiary,
            title: 'Backup & restore',
            value: 'One JSON file, saved where you choose',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const BackupPage()),
            ),
          ),

          _GroupLabel('About', colour: scheme.tertiary),
          _Tile(
            icon: Icons.auto_stories_outlined,
            colour: scheme.tertiary,
            title: 'How Prahar works',
            value: 'The tabs, and why blocks land where they do',
            onTap: () => HowItWorks.open(context),
          ),

          const SizedBox(height: 34),
          const Center(
            child: PraharLogo(markSize: 36, filled: false, animated: true),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(28, 10, 28, 16),
            child: Text(
              'Everything stays on this device. No account, no server, '
              'no subscription.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.outline,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Theme, cards and materials, on a page of their own.
///
/// These were inline on the Settings list, on the argument that their effect
/// is visible on the screen you are standing on. True, and it still put the
/// three least consequential settings above the hours the planner runs on,
/// and gave that one screen a shape nothing else in the app has. They keep
/// the apply-on-tap behaviour here, where a page of appearance controls is
/// exactly what the reader came for.
class AppearancePage extends StatelessWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Look')),
      body: ReadableColumn(
        child: ListView(
          padding: const EdgeInsets.only(top: 12, bottom: 40),
          children: [
            const _Masthead(),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: ThemeToggle(
                selected: state.prefs.themeChoice,
                // The amber the bottom bar marks its selection with. It was
                // the indigo primary, which said "selected" in a second
                // dialect.
                accent: scheme.tertiary,
                onAccent: scheme.onTertiary,
                onChanged: (c) => savePrefs(
                  context,
                  state,
                  state.prefs.copyWith(themeChoice: c),
                ),
              ),
            ),
            _InlineChoice(
              title: 'Cards',
              subtitle: PraharTheme.describeCards(state.prefs.cardStyle).$2,
              options: [
                for (final c in CardStyle.values)
                  (
                    PraharTheme.describeCards(c).$1,
                    c == state.prefs.cardStyle,
                    c,
                  ),
              ],
              colour: scheme.tertiary,
              onPick: (v) => savePrefs(
                context,
                state,
                state.prefs.copyWith(cardStyle: v as CardStyle),
              ),
              onOpen: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const CardStylePage()),
              ),
            ),
            _InlineChoice(
              title: 'Materials',
              subtitle: state.prefs.materialChoice == MaterialChoice.glass
                  ? 'Frosted glass on the bar, the nav and panels'
                  : 'Flat surfaces throughout',
              options: [
                (
                  'Matte',
                  state.prefs.materialChoice == MaterialChoice.matte,
                  MaterialChoice.matte,
                ),
                (
                  'Glass',
                  state.prefs.materialChoice == MaterialChoice.glass,
                  MaterialChoice.glass,
                ),
              ],
              colour: scheme.tertiary,
              onPick: (v) => savePrefs(
                context,
                state,
                state.prefs.copyWith(materialChoice: v as MaterialChoice),
              ),
              onOpen: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const MaterialStylePage(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// One accent, not four.
//
// The first version gave each group its own hue — indigo, amber, cyan,
// violet — on the theory that colour lets the eye find a section without
// reading it. It does, and it also invented three colours the app does not
// otherwise speak, which is a different app's screen wearing this one's name.
// The palette is indigo for structure and amber for effort; a settings group
// is neither, so every group borrows the amber that the nav bar and the theme
// toggle already use to mean "this one".

/// The band at the top: the mark, and the three choices that make the app look
/// the way it currently looks.
///
/// The old screen opened on the word SCHEDULE in grey capitals. This opens on
/// what you have already decided, which is the thing a Look screen is for.
class _Masthead extends StatelessWidget {
  const _Masthead();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final choices = [
      switch (state.prefs.themeChoice) {
        ThemeChoice.light => 'Light',
        ThemeChoice.dark => 'Dark',
        ThemeChoice.system => 'Auto',
      },
      PraharTheme.describeCards(state.prefs.cardStyle).$1,
      state.prefs.materialChoice == MaterialChoice.glass ? 'Glass' : 'Matte',
    ];

    // The panel *is* the preview.
    //
    // It was a Container with its own gradient and its own border, which meant
    // it looked identical whatever the card style was — the one surface on the
    // screen that had to demonstrate the setting was the one ignoring it. It
    // is a StyledPanel now, the same surface Today's hero uses, so changing
    // Cards or Materials changes this card in front of you.
    //
    // The gradient survives as a chip behind the mark rather than a wash over
    // the whole surface: a gradient across the panel would hide exactly the
    // fill differences between plain, tinted and lifted that it is here to
    // show.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: StyledPanel(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    scheme.primary.withValues(alpha: 0.26),
                    scheme.tertiary.withValues(alpha: 0.18),
                  ],
                ),
              ),
              child: const AnimatedPraharMark(size: 34, playOnAppear: false),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Look',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    choices.join('  ·  '),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'This card is drawn in the style you pick.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.outline,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A section heading with its group's colour on it.
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text, {required this.colour});

  final String text;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 10),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            text.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A settings row that carries its group's colour in the icon chip.
class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.colour,
    required this.title,
    required this.value,
    required this.onTap,
    this.warn = false,
  });

  final IconData icon;
  final Color colour;
  final String title;
  final String value;
  final VoidCallback onTap;

  /// Draws the value in the error colour. Used for exactly one thing: alarms
  /// that cannot fire on time.
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = warn ? theme.colorScheme.error : colour;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PraharTheme.cardRadius),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
            child: Row(
              children: [
                // A tinted chip rather than a bare grey glyph. Eight identical
                // grey icons is what made the old screen unreadable at a
                // glance; eight coloured ones would be noise, so the colour
                // belongs to the group, not the row.
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: tint.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 20, color: tint),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: warn
                              ? theme.colorScheme.error
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: theme.colorScheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A choice made on this screen rather than on a page behind it.
///
/// Cards and Materials were rows that named their current value and hid the
/// alternatives one tap away — which is the wrong shape for a setting whose
/// entire effect is visible on the screen you are standing on. Picking here
/// applies immediately; the full previews are still a tap away for anyone who
/// wants to see each style drawn at size.
class _InlineChoice extends StatelessWidget {
  const _InlineChoice({
    required this.title,
    required this.subtitle,
    required this.options,
    required this.colour,
    required this.onPick,
    required this.onOpen,
  });

  final String title;
  final String subtitle;

  /// (label, selected, value)
  final List<(String, bool, Object)> options;
  final Color colour;
  final ValueChanged<Object> onPick;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.bodyLarge),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'See each one drawn',
                    onPressed: onOpen,
                    icon: Icon(
                      Icons.open_in_full_rounded,
                      size: 18,
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Scrolls rather than wraps: five card styles will not fit on a
              // phone, and a wrapped second row of chips reads as a second
              // group of things.
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(right: 8),
                  itemCount: options.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, i) {
                    final (label, selected, value) = options[i];
                    return _Chip(
                      label: label,
                      selected: selected,
                      colour: colour,
                      onTap: () => onPick(value),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.colour,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Animated so a tap reads as the same gesture the theme toggle uses; the
    // whole screen should feel like one control surface.
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? colour.withValues(alpha: 0.20)
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.6,
                ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? colour : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected ? colour : theme.colorScheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
