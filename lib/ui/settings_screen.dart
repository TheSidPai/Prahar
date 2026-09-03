import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/backup.dart';
import '../domain/format.dart';
import '../domain/preferences.dart';
import '../notifications/notifier.dart';
import '../state/app_state.dart';
import 'busy_slots_screen.dart';
import 'how_it_works.dart';
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
    final weekTotal = List.generate(7, (i) => weekly.minutesByWeekday[i + 1] ?? 0)
        .fold(0, (a, b) => a + b);

    Widget row({
      required IconData icon,
      required String title,
      required String value,
      required VoidCallback onTap,
    }) =>
        Padding(
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

    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        group('Schedule'),
        row(
          icon: Icons.schedule,
          title: 'Study time',
          value: '${formatMinutes(weekTotal)} a week',
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                  builder: (_) => const _StudyTimePage())),
        ),
        row(
          icon: Icons.watch_later_outlined,
          title: 'Study window',
          value:
              '${formatClock(state.prefs.dayStartMinute)} – ${formatClock(state.prefs.dayEndMinute)}, '
              '${state.prefs.blockMinutes} min blocks',
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                  builder: (_) => const _StudyWindowPage())),
        ),
        row(
          icon: Icons.event_busy_outlined,
          title: 'Busy slots',
          value: state.availability.busy.isEmpty
              ? 'None'
              : '${state.availability.busy.length} recorded',
          onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                  builder: (_) => const BusySlotsScreen())),
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
              MaterialPageRoute<void>(
                  builder: (_) => const _RemindersPage())),
        ),

        group('Appearance'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: _ThemeToggle(
            selected: state.prefs.themeChoice,
            onChanged: (c) => _savePrefs(
                context, state, state.prefs.copyWith(themeChoice: c)),
          ),
        ),
        row(
          icon: Icons.text_fields_outlined,
          title: 'Font',
          value: PraharTheme.describe(state.prefs.fontChoice).$1,
          onTap: () => Navigator.push(context,
              MaterialPageRoute<void>(builder: (_) => const _FontPage())),
        ),
        row(
          icon: Icons.blur_on,
          title: 'Materials',
          value: state.prefs.materialChoice == MaterialChoice.glass
              ? 'Glass (preview) — nav, sheets, Today header'
              : 'Matte',
          onTap: () => Navigator.push(context,
              MaterialPageRoute<void>(builder: (_) => const _MaterialPage())),
        ),

        group('Data'),
        row(
          icon: Icons.backup_outlined,
          title: 'Backup & restore',
          value: 'Export or restore a JSON file',
          onTap: () => Navigator.push(context,
              MaterialPageRoute<void>(builder: (_) => const _BackupPage())),
        ),

        group('About'),
        row(
          icon: Icons.help_outline,
          title: 'How Prahar works',
          value: 'Guide to the tabs and scheduling',
          onTap: () => HowItWorks.open(context),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Text(
            'Everything stays on this device. No account, no server, no '
            'subscription.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.outline),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ subpages

class _StudyTimePage extends StatelessWidget {
  const _StudyTimePage();

  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
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
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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

class _StudyWindowPage extends StatelessWidget {
  const _StudyWindowPage();

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
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          _TimeRow(
            label: 'Earliest start',
            minute: state.prefs.dayStartMinute,
            onPicked: (m) => _savePrefs(
                context, state, state.prefs.copyWith(dayStartMinute: m)),
          ),
          _TimeRow(
            label: 'Latest end',
            minute: state.prefs.dayEndMinute,
            onPicked: (m) => _savePrefs(
                context, state, state.prefs.copyWith(dayEndMinute: m)),
          ),
          _StepRow(
            label: 'Block length',
            value: state.prefs.blockMinutes,
            min: 15,
            max: 120,
            step: 5,
            onChanged: (v) => _savePrefs(
                context, state, state.prefs.copyWith(blockMinutes: v)),
          ),
          _StepRow(
            label: 'Break between',
            value: state.prefs.breakMinutes,
            min: 0,
            max: 30,
            step: 5,
            onChanged: (v) => _savePrefs(
                context, state, state.prefs.copyWith(breakMinutes: v)),
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
class _ThemeToggle extends StatelessWidget {
  const _ThemeToggle({required this.selected, required this.onChanged});

  final ThemeChoice selected;
  final ValueChanged<ThemeChoice> onChanged;

  static const _options = <(ThemeChoice, IconData, String)>[
    (ThemeChoice.light, Icons.light_mode_rounded, 'Light'),
    (ThemeChoice.system, Icons.auto_awesome_rounded, 'Auto'),
    (ThemeChoice.dark, Icons.dark_mode_rounded, 'Dark'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final index = _options.indexWhere((o) => o.$1 == selected);

    return LayoutBuilder(builder: (context, cons) {
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
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.24),
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
                                    ? theme.colorScheme.onPrimary
                                    : theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              o.$3,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: o.$1 == selected
                                    ? theme.colorScheme.onPrimary
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
    });
  }
}

class _MaterialPage extends StatelessWidget {
  const _MaterialPage();

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
            'Glass affects the bottom nav, the Today header and every modal '
            'sheet; everything else stays matte on purpose (contrast between '
            'materials is what carries the effect).',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          for (final entry in const [
            (MaterialChoice.matte, 'Matte', Icons.rectangle_outlined,
                'Flat surfaces, hairline borders. Restrained and quick.'),
            (MaterialChoice.glass, 'Glass', Icons.blur_on,
                'Translucent surfaces with a backdrop blur. Frosted, layered.'),
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
                      ? Icon(Icons.check_circle,
                          color: theme.colorScheme.primary, size: 20)
                      : null,
                  onTap: () => _savePrefs(context, state,
                      state.prefs.copyWith(materialChoice: entry.$1)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BackupPage extends StatefulWidget {
  const _BackupPage();

  @override
  State<_BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends State<_BackupPage> {
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
              subtitle: const Text('Writes to /Download/Prahar on the phone'),
              onTap: () async {
                try {
                  final io = BackupIO(state.db);
                  final path = await io.exportToFile();
                  setState(() {
                    _lastExport = path;
                    _message = 'Exported to $path';
                  });
                } catch (e) {
                  setState(() => _message = 'Export failed: $e');
                }
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Restore'),
              subtitle: const Text(
                  'Reads /Download/Prahar/prahar-restore.json — put a backup '
                  'there first, then tap.'),
              onTap: () => _confirmRestore(context, state),
            ),
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            Text(_message!, style: theme.textTheme.bodySmall),
          ],
          if (_lastExport != null) ...[
            const SizedBox(height: 6),
            Text(
              'Open your file manager > Downloads > Prahar to send it '
              'somewhere safe.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRestore(BuildContext context, AppState state) async {
    // Restore is destructive by design (see BackupIO.import), so the
    // confirmation is deliberate rather than a nicety.
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Replace everything?'),
        content: const Text(
          'This deletes your current subjects, topics, history and settings, '
          'and replaces them with the contents of the backup file. It cannot '
          'be undone. Export first if unsure.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final path = '/sdcard/Download/Prahar/prahar-restore.json';
      final json = await File(path).readAsString();
      final io = BackupIO(state.db);
      final report = await io.import(json);
      await state.load();
      if (mounted) setState(() => _message = '$report');
    } catch (e) {
      if (mounted) setState(() => _message = 'Restore failed: $e');
    }
  }
}

class _FontPage extends StatelessWidget {
  const _FontPage();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Font')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 16),
            child: Text(
              'Every option shows a real specimen. Tap to try — the whole app '
              'restyles immediately, so you can browse other tabs and come '
              'back.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          for (final choice in FontChoice.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _FontCard(
                choice: choice,
                selected: choice == state.prefs.fontChoice,
                onTap: () => _savePrefs(
                    context, state, state.prefs.copyWith(fontChoice: choice)),
              ),
            ),
        ],
      ),
    );
  }
}

/// A live specimen of the family, so the choice is made on how it looks and
/// not on the name. Two lines rendered at heading and body sizes cover most
/// of what the reader will encounter in the app.
class _FontCard extends StatelessWidget {
  const _FontCard({
    required this.choice,
    required this.selected,
    required this.onTap,
  });

  final FontChoice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desc = PraharTheme.describe(choice);
    final baseText = theme.textTheme;
    // Render the specimen in the family being previewed, so this card is a
    // true representation regardless of the currently applied font.
    final family = PraharTheme.fontFor(choice, baseText);

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Expanded(
                  child: Text(desc.$1, style: baseText.titleMedium),
                ),
                if (selected)
                  Icon(Icons.check_circle,
                      color: theme.colorScheme.primary, size: 20),
              ]),
              Text(
                desc.$2,
                style: baseText.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
              const SizedBox(height: 14),
              Text(
                'Ch 4 — Aldehydes',
                style: family.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.6,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Physics needs 47 min a day to be ready by 24 Oct',
                style: family.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RemindersPage extends StatelessWidget {
  const _RemindersPage();

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: const Icon(Icons.notifications_active_outlined),
            title: const Text('Re-request permissions'),
            subtitle: const Text(
                'Includes "Alarms & reminders", which Android hides in a '
                'separate screen'),
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
                'works without waiting for a real block'),
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
Future<void> _savePrefs(
    BuildContext context, AppState state, Prefs next) async {
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
            onPressed:
                value - step >= min ? () => onChanged(value - step) : null,
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
            onPressed:
                value + step <= max ? () => onChanged(value + step) : null,
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
