import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:flutter/services.dart';

import '../data/backup.dart';
import '../data/file_exchange.dart';
import '../domain/format.dart';
import '../domain/preferences.dart';
import '../notifications/notifier.dart';
import '../state/app_state.dart';
import 'brand.dart';
import 'busy_slots_screen.dart';
import 'glass.dart';
import 'how_it_works.dart';
import 'layout.dart';
import 'theme.dart';

/// A compact index of settings, not a wall of controls.
///
/// The previous screen exposed every slider and step-button at once. This one
/// is a set of rows, each showing the current value and opening a focused
/// subpage. It reads more like a system Settings app, where the reveal happens
/// on tap rather than by scroll, and it makes room to add categories later
/// without the list turning into wallpaper.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final weekly = state.availability;
    final weekTotal = List.generate(
      7,
      (i) => weekly.minutesByWeekday[i + 1] ?? 0,
    ).fold(0, (a, b) => a + b);

    Widget row({
      required IconData icon,
      required String title,
      required String value,
      required VoidCallback onTap,
    }) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        child: ListTile(
          leading: Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          title: Text(title),
          subtitle: Text(value),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      ),
    );

    Widget group(String label) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
          letterSpacing: 1.0,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

    // Settings rows are a column of short lines; stretched across a tablet the
    // value on the right ends up a hand's width from the label on the left.
    return ReadableColumn(
      child: ListView(
        padding: EdgeInsets.only(top: glassTopInset(context), bottom: 90),
        children: [
          group('Schedule'),
          row(
            icon: Icons.schedule,
            title: 'Study time',
            value: '${formatMinutes(weekTotal)} a week',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const StudyTimePage()),
            ),
          ),
          row(
            icon: Icons.watch_later_outlined,
            title: 'Study window',
            value:
                '${formatClock(state.prefs.dayStartMinute)} – ${formatClock(state.prefs.dayEndMinute)}, '
                '${state.prefs.blockMinutes} min blocks',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const StudyWindowPage()),
            ),
          ),
          row(
            icon: Icons.event_busy_outlined,
            title: 'Busy slots',
            value: state.availability.busy.isEmpty
                ? 'None'
                : '${state.availability.busy.length} recorded',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const BusySlotsScreen()),
            ),
          ),

          group('Reminders'),
          row(
            icon: Icons.notifications_outlined,
            title: 'Notifications',
            value: state.exactAlarmsAllowed
                ? 'Exact timing allowed'
                : 'Exact alarms blocked — may arrive late',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const RemindersPage()),
            ),
          ),

          group('Appearance'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: ThemeToggle(
              selected: state.prefs.themeChoice,
              onChanged: (c) => savePrefs(
                context,
                state,
                state.prefs.copyWith(themeChoice: c),
              ),
            ),
          ),
          row(
            icon: Icons.dashboard_outlined,
            title: 'Cards',
            value: PraharTheme.describeCards(state.prefs.cardStyle).$1,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const CardStylePage()),
            ),
          ),
          row(
            icon: Icons.blur_on,
            title: 'Materials',
            value: state.prefs.materialChoice == MaterialChoice.glass
                ? 'Glass (preview) — nav, sheets, panels'
                : 'Matte',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const MaterialStylePage(),
              ),
            ),
          ),

          group('Data'),
          row(
            icon: Icons.backup_outlined,
            title: 'Backup & restore',
            value: 'Export or restore a JSON file',
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const BackupPage()),
            ),
          ),

          group('About'),
          row(
            icon: Icons.help_outline,
            title: 'How Prahar works',
            value: 'Guide to the tabs and scheduling',
            onTap: () => HowItWorks.open(context),
          ),
          // Brand footer. Mark + wordmark centred, one line of provenance
          // beneath. Reads as a signature at the end of a document rather
          // than an About card competing for attention.
          Padding(
            padding: const EdgeInsets.only(top: 40, bottom: 12),
            child: Center(child: PraharLogo(markSize: 40, filled: false)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Text(
              'Everything stays on this device. No account, no server, no '
              'subscription.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ subpages

class StudyTimePage extends StatelessWidget {
  const StudyTimePage({super.key});

  static const _weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final weekly = state.availability;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Study time')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Text(
              'Minutes you can genuinely study each day. Be honest — an '
              'optimistic number just produces a plan you fall behind on.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (var day = 1; day <= 7; day++)
            _DaySlider(
              label: _weekdayNames[day - 1],
              minutes: weekly.minutesByWeekday[day] ?? 0,
              onChanged: (m) => state.setWeekdayMinutes(day, m),
            ),
        ],
      ),
    );
  }
}

class StudyWindowPage extends StatelessWidget {
  const StudyWindowPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Study window')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
            child: Text(
              'The hours blocks may be placed between, and how long each block '
              'is. Set the hours to when you are actually free.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          _TimeRow(
            label: 'Earliest start',
            minute: state.prefs.dayStartMinute,
            onPicked: (m) => savePrefs(
              context,
              state,
              state.prefs.copyWith(dayStartMinute: m),
            ),
          ),
          _TimeRow(
            label: 'Latest end',
            minute: state.prefs.dayEndMinute,
            onPicked: (m) => savePrefs(
              context,
              state,
              state.prefs.copyWith(dayEndMinute: m),
            ),
          ),
          _StepRow(
            label: 'Block length',
            value: state.prefs.blockMinutes,
            min: 15,
            max: 120,
            step: 5,
            onChanged: (v) => savePrefs(
              context,
              state,
              state.prefs.copyWith(blockMinutes: v),
            ),
          ),
          _StepRow(
            label: 'Break between',
            value: state.prefs.breakMinutes,
            min: 0,
            max: 30,
            step: 5,
            onChanged: (v) => savePrefs(
              context,
              state,
              state.prefs.copyWith(breakMinutes: v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text(
              '${formatMinutes(state.prefs.windowMinutes)} available each day, '
              'in blocks of ${state.prefs.blockMinutes} min.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// A pill-shaped three-way toggle: sun, moon, auto. Sits inline in the
/// Settings list, no subpage — a three-option choice does not deserve one.
/// The selected pill slides between positions with a spring, so the change of
/// value feels physical rather than a checkbox flip.
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({
    super.key,
    required this.selected,
    required this.onChanged,
    this.accent,
    this.onAccent,
  });

  final ThemeChoice selected;
  final ValueChanged<ThemeChoice> onChanged;

  /// The moving selector's fill. Defaults to the indigo primary, which is what
  /// Settings has always used; Look passes the amber the nav bar marks its own
  /// selection with, so one idea — "this is the thing you chose" — is one
  /// colour throughout the app.
  final Color? accent;

  /// What is legible on [accent].
  final Color? onAccent;

  static const _options = <(ThemeChoice, IconData, String)>[
    (ThemeChoice.light, Icons.light_mode_rounded, 'Light'),
    (ThemeChoice.system, Icons.auto_awesome_rounded, 'Auto'),
    (ThemeChoice.dark, Icons.dark_mode_rounded, 'Dark'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final index = _options.indexWhere((o) => o.$1 == selected);
    final fill = accent ?? theme.colorScheme.primary;
    final ink = onAccent ?? theme.colorScheme.onPrimary;

    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth;
        final segW = w / _options.length;

        return Container(
          height: 56,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(28),
          ),
          padding: const EdgeInsets.all(4),
          child: Stack(
            children: [
              // The moving selector. AnimatedPositioned rather than
              // AnimatedContainer so a rapid re-tap still animates from the
              // current position, not from the target.
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: index * (segW - 8 / _options.length),
                top: 0,
                bottom: 0,
                width: segW - 8,
                child: Container(
                  decoration: BoxDecoration(
                    color: fill,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: fill.withValues(
                          alpha: 0.24,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final o in _options)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(o.$1),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                child: Icon(
                                  o.$2,
                                  key: ValueKey('${o.$1}-${o.$1 == selected}'),
                                  size: 18,
                                  color: o.$1 == selected
                                      ? ink
                                      : theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                o.$3,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: o.$1 == selected
                                      ? ink
                                      : theme.colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// Not `MaterialPage`: Flutter exports a class by that name from
// material.dart, and any file importing both cannot say which it means.
class MaterialStylePage extends StatelessWidget {
  const MaterialStylePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Materials')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Text(
            'Two visual languages. Toggle to preview — the change is instant. '
            'Glass affects the bottom nav, every modal sheet, and the three '
            'summary panels: the Today header, the feasibility banner and a '
            "subject's status. Lists and cards stay matte on purpose — the "
            'contrast between materials is what carries the effect.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          for (final entry in const [
            (
              MaterialChoice.matte,
              'Matte',
              Icons.rectangle_outlined,
              'Flat surfaces, hairline borders. Restrained and quick.',
            ),
            (
              MaterialChoice.glass,
              'Glass',
              Icons.blur_on,
              'Translucent surfaces with a backdrop blur. Frosted, layered.',
            ),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: entry.$1 == state.prefs.materialChoice
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    width: entry.$1 == state.prefs.materialChoice ? 2 : 1,
                  ),
                ),
                child: ListTile(
                  leading: Icon(entry.$3),
                  title: Text(entry.$2),
                  subtitle: Text(entry.$4),
                  trailing: entry.$1 == state.prefs.materialChoice
                      ? Icon(
                          Icons.check_circle,
                          color: theme.colorScheme.primary,
                          size: 20,
                        )
                      : null,
                  onTap: () => savePrefs(
                    context,
                    state,
                    state.prefs.copyWith(materialChoice: entry.$1),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class BackupPage extends StatefulWidget {
  const BackupPage({super.key});

  @override
  State<BackupPage> createState() => BackupPageState();
}

class BackupPageState extends State<BackupPage> {
  String? _lastExport;
  String? _message;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Backup & restore')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Text(
            'A single JSON file with everything the app knows — subjects, '
            'topics, availability, busy slots, settings. Local-first means '
            'this is your only safety net.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('Export'),
              subtitle: const Text('Choose where to save it'),
              onTap: () => _export(state),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Restore'),
              subtitle: const Text('Pick a backup file to restore from'),
              onTap: () => _restore(state),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!, style: theme.textTheme.bodySmall),
          ],
          if (_lastExport != null) ...[
            const SizedBox(height: 6),
            Text(
              'Keep a copy somewhere other than this phone. A backup that '
              'only exists on the device it is backing up is not a backup.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _export(AppState state) async {
    try {
      final io = BackupIO(state.db);
      final json = await io.serialise();
      final stamp = DateTime.now().toIso8601String().split('T').first;

      final saved = await FileExchange.save(
        suggestedName: 'prahar-backup-$stamp.json',
        contents: json,
      );
      if (!mounted) return;

      // Null means the picker was dismissed, which is not a failure and does
      // not deserve a message.
      if (saved == null) return;
      setState(() {
        _lastExport = saved;
        _message = 'Saved as $saved';
      });
    } on MissingPluginException {
      // No picker on this platform — desktop, or a test binding. Fall back to
      // the old behaviour rather than leaving the user with nothing.
      try {
        final path = await BackupIO(state.db).exportToFile();
        if (mounted) {
          setState(() {
            _lastExport = path;
            _message = 'Exported to $path';
          });
        }
      } catch (e) {
        if (mounted) setState(() => _message = 'Export failed: $e');
      }
    } catch (e) {
      if (mounted) setState(() => _message = 'Export failed: $e');
    }
  }

  // Takes no BuildContext: the dialog opens after an await, so it has to use
  // this State's own context behind its own `mounted` check.
  Future<void> _restore(AppState state) async {
    // The file is chosen first and confirmed second. Asking "replace
    // everything?" before knowing whether the user even has a backup to hand
    // makes them affirm a destructive action to reach a file browser they may
    // then cancel out of.
    final String? json;
    try {
      json = await FileExchange.open();
    } catch (e) {
      if (mounted) setState(() => _message = 'Could not open the file: $e');
      return;
    }
    if (json == null || !mounted) return;

    // Restore is destructive by design (see BackupIO.import), so the
    // confirmation is deliberate rather than a nicety.
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace everything?'),
        content: const Text(
          'This deletes your current subjects, topics, history and settings, '
          'and replaces them with the contents of the file you picked. It '
          'cannot be undone. Export first if unsure.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final report = await BackupIO(state.db).import(json);
      await state.load();
      if (mounted) setState(() => _message = '$report');
    } catch (e) {
      if (mounted) setState(() => _message = 'Restore failed: $e');
    }
  }
}

/// Five ideas about how a card separates itself from the page, each drawn as
/// a real card rather than described in words.
///
/// The specimen is a Progress row — the densest card in the app and the one
/// that appears most often — so the choice is made on the thing it actually
/// affects. Tapping applies immediately, so the other tabs can be browsed
/// before deciding: the font picker worked exactly this way, and being able to
/// *use* the app in a style beats studying a swatch of it.
class CardStylePage extends StatelessWidget {
  const CardStylePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Cards')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 18),
            child: Text(
              'Every list in Prahar is made of cards, so this sets the texture '
              'of the whole app. Each sample below is drawn in its own style. '
              'Tap one to apply it everywhere — you can wander through the '
              'other tabs and come back.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          for (final style in CardStyle.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 22),
              child: _CardSpecimen(
                style: style,
                selected: style == state.prefs.cardStyle,
                onTap: () => savePrefs(
                  context,
                  state,
                  state.prefs.copyWith(cardStyle: style),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CardSpecimen extends StatelessWidget {
  const _CardSpecimen({
    required this.style,
    required this.selected,
    required this.onTap,
  });

  final CardStyle style;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final outer = Theme.of(context);
    final desc = PraharTheme.describeCards(style);

    // The specimen is rendered under a theme built for *this* style, so it
    // shows the real thing regardless of which style is currently applied.
    final preview = PraharTheme.of(
      outer.brightness,
      material: context.select<AppState, MaterialChoice>(
        (s) => s.prefs.materialChoice,
      ),
      cardStyle: style,
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                desc.$1,
                style: outer.textTheme.titleSmall?.copyWith(
                  color: selected ? outer.colorScheme.tertiary : null,
                ),
              ),
              const SizedBox(width: 8),
              if (selected)
                Icon(
                  Icons.check_circle,
                  size: 16,
                  color: outer.colorScheme.tertiary,
                ),
              const Spacer(),
              Text(
                desc.$2,
                style: outer.textTheme.bodySmall?.copyWith(
                  color: outer.colorScheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Two stacked specimens: a single card can look fine in isolation
          // and turn into a grid the moment it has a neighbour, which is the
          // failure mode that made hairlines the original choice.
          Theme(
            data: preview,
            child: Builder(
              builder: (context) => Container(
                // The page behind the cards must be the scaffold colour, or a
                // borderless style is being judged against the wrong ground.
                color: preview.scaffoldBackgroundColor,
                padding: const EdgeInsets.all(12),
                child: const Column(
                  children: [
                    _SpecimenCard(
                      name: 'Data Structures and Algorithms',
                      meta: '5h 10m of 10h · 0 of 1 topics done',
                      deadline: '49 days left · needs 6m a day',
                      progress: 0.52,
                      color: Color(0xFFE07A3E),
                    ),
                    SizedBox(height: 12),
                    _SpecimenCard(
                      name: 'Indian Music',
                      meta: '40m of 4h · 0 of 1 topics done',
                      deadline: 'exam tomorrow at 09:00 · needs 47m a day',
                      progress: 0.17,
                      color: Color(0xFF3BA7C4),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A miniature of the Progress card, kept deliberately close to the real one:
/// a specimen that flatters itself is worse than no specimen.
class _SpecimenCard extends StatelessWidget {
  const _SpecimenCard({
    required this.name,
    required this.meta,
    required this.deadline,
    required this.progress,
    required this.color,
  });

  final String name;
  final String meta;
  final String deadline;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: theme.textTheme.titleMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, size: 18),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(meta, style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              deadline,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RemindersPage extends StatelessWidget {
  const RemindersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.nightlight_outlined),
            title: const Text('Evening digest'),
            subtitle: const Text(
              "One quiet notification with tomorrow's blocks, so the plan "
              'reaches you without you having to open anything',
            ),
            value: state.prefs.digestEnabled,
            onChanged: (on) => savePrefs(
              context,
              state,
              state.prefs.copyWith(digestEnabled: on),
            ),
          ),
          if (state.prefs.digestEnabled)
            ListTile(
              leading: const Icon(Icons.schedule_outlined),
              title: const Text('Digest time'),
              subtitle: const Text('Late enough that the day is done'),
              trailing: Text(
                formatClock(state.prefs.digestMinute),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              onTap: () async {
                final picked = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(
                    hour: state.prefs.digestMinute ~/ 60,
                    minute: state.prefs.digestMinute % 60,
                  ),
                );
                if (picked != null && context.mounted) {
                  await savePrefs(
                    context,
                    state,
                    state.prefs.copyWith(
                      digestMinute: picked.hour * 60 + picked.minute,
                    ),
                  );
                }
              },
            ),
          const Divider(height: 24),
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Re-request permissions'),
            subtitle: const Text(
              'Includes "Alarms & reminders", which Android hides in a '
              'separate screen',
            ),
            onTap: () async {
              await state.notifier.requestPermissions();
              await state.refreshAlarms();
            },
          ),
          ListTile(
            leading: const Icon(Icons.notifications_none),
            title: const Text('Send a test reminder'),
            subtitle: const Text(
              'Fires in 1 minute. The only way to check delivery actually '
              'works without waiting for a real block',
            ),
            onTap: () async {
              final when = await state.notifier.scheduleTest();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Test reminder set for '
                      '${formatClock(when.hour * 60 + when.minute)}. '
                      'Lock the phone and wait.',
                    ),
                    duration: const Duration(seconds: 6),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: const Text('Reschedule all reminders'),
            subtitle: Text(
              'One reminder per study block for the next ${Notifier.windowDays} '
              'days. ${state.exactAlarmsAllowed ? "Exact timing is allowed." : "Exact alarms are blocked — reminders may arrive late."}',
            ),
            onTap: () async {
              await state.refreshAlarms();
              final pending = await state.notifier.pendingCount();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '$pending reminders set — one for each study block in the '
                      'next ${Notifier.windowDays} days.',
                    ),
                    duration: const Duration(seconds: 5),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ shared

/// Saves a preference, refusing a window too narrow to hold a single block.
Future<void> savePrefs(
  BuildContext context,
  AppState state,
  Prefs next,
) async {
  final ok = await state.updatePrefs(next);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'That window is too narrow to fit a '
          '${next.blockMinutes} min block. Widen the hours, or shorten the '
          'block first.',
        ),
        duration: const Duration(seconds: 5),
      ),
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.minute,
    required this.onPicked,
  });

  final String label;
  final int minute;
  final ValueChanged<int> onPicked;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: Text(
        formatClock(minute),
        style: Theme.of(context).textTheme.titleMedium,
      ),
      onTap: () async {
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
        );
        if (picked != null) onPicked(picked.hour * 60 + picked.minute);
      },
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: value - step >= min
                ? () => onChanged(value - step)
                : null,
          ),
          SizedBox(
            width: 56,
            child: Text(
              '$value min',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: value + step <= max
                ? () => onChanged(value + step)
                : null,
          ),
        ],
      ),
    );
  }
}

class _DaySlider extends StatelessWidget {
  const _DaySlider({
    required this.label,
    required this.minutes,
    required this.onChanged,
  });

  final String label;
  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
          Expanded(
            child: Slider(
              value: minutes.toDouble(),
              max: 720,
              divisions: 24,
              label: formatMinutes(minutes),
              onChanged: (v) => onChanged(v.round()),
            ),
          ),
          SizedBox(
            width: 56,
            child: Text(
              formatMinutes(minutes),
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
