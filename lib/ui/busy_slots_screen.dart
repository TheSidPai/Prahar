import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/format.dart';
import '../domain/models.dart' show dateOnly;
import '../domain/schedule.dart';
import '../state/app_state.dart';
import 'widgets.dart';

/// Times the student is unavailable. Subtracted from the study window so blocks
/// don't land during class or lunch — a reminder that fires while a person is
/// in a lecture is the fastest way to teach them the schedule is fiction.
class BusySlotsScreen extends StatelessWidget {
  const BusySlotsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final slots = state.availability.busy;

    return Scaffold(
      appBar: AppBar(title: const Text('Busy slots')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: slots.isEmpty
          ? const EmptyState(
              // The FAB below is the add affordance; a second button in the
              // centre pointing at the same sheet is redundant and looks like
              // a different action.
              icon: Icons.event_busy_outlined,
              title: 'No busy slots yet',
              message: 'Tap Add to record class hours, lunch, a shift — '
                  'anything the schedule should route around. Weekly repeats '
                  'or a single date.',
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Text(
                    '${slots.length} slot${slots.length == 1 ? '' : 's'}. '
                    'Study blocks are placed around these.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                for (final s in [...slots]..sort(_bySort))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Card(
                      child: ListTile(
                        title: Text(s.label.isEmpty ? 'Busy' : s.label),
                        subtitle: Text(
                          '${formatClock(s.startMinute)} – '
                          '${formatClock(s.endMinute)}  ·  ${_when(s)}',
                        ),
                        onTap: () => _showSheet(context, existing: s),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  static int _bySort(BusySlot a, BusySlot b) {
    // Weekly rows first, sorted by weekday then time; one-offs by date.
    if (a.repeatsWeekly != b.repeatsWeekly) {
      return a.repeatsWeekly ? -1 : 1;
    }
    if (a.repeatsWeekly) {
      final wd = a.weekday!.compareTo(b.weekday!);
      return wd != 0 ? wd : a.startMinute.compareTo(b.startMinute);
    }
    return a.date!.compareTo(b.date!);
  }

  static String _when(BusySlot s) {
    if (s.repeatsWeekly) {
      const names = [
        'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
      ];
      return 'every ${names[s.weekday! - 1]}';
    }
    return formatDateFull(s.date!);
  }
}

enum _Repeat { weekly, oneOff }

Future<void> _showSheet(BuildContext context, {BusySlot? existing}) async {
  final state = context.read<AppState>();
  final label = TextEditingController(text: existing?.label ?? '');
  var start = existing?.startMinute ?? 13 * 60;
  var end = existing?.endMinute ?? 15 * 60;
  var repeat = (existing?.repeatsWeekly ?? true) ? _Repeat.weekly : _Repeat.oneOff;
  // A set, because "class every Mon–Fri" is one slot to a student, not five.
  // When editing a single-day slot the set starts with that one day; when
  // adding, it starts with today so a tap-tap-save works.
  final weekdays = <int>{
    if (existing?.weekday != null) existing!.weekday!,
    if (existing == null) DateTime.now().weekday,
  };
  var date = existing?.date ?? dateOnly(DateTime.now());

  Future<void> pick(BuildContext ctx, bool isStart, StateSetter set) async {
    final t = await showTimePicker(
      context: ctx,
      initialTime: TimeOfDay(
        hour: (isStart ? start : end) ~/ 60,
        minute: (isStart ? start : end) % 60,
      ),
    );
    if (t != null) {
      set(() {
        if (isStart) {
          start = t.hour * 60 + t.minute;
          // Pull end forward if the user made it earlier than the start —
          // an inverted range means a zero-length slot the planner ignores.
          if (end <= start) end = (start + 60).clamp(0, 24 * 60);
        } else {
          end = t.hour * 60 + t.minute;
          if (end <= start) start = (end - 60).clamp(0, 24 * 60);
        }
      });
    }
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: StatefulBuilder(
        builder: (context, set) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existing == null ? 'New busy slot' : 'Edit busy slot',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: label,
                autofocus: existing == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  hintText: 'Class, lunch, football',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => pick(context, true, set),
                    child: Text('From  ${formatClock(start)}'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => pick(context, false, set),
                    child: Text('To  ${formatClock(end)}'),
                  ),
                ),
              ]),
              const SizedBox(height: 16),
              SegmentedButton<_Repeat>(
                segments: const [
                  ButtonSegment(value: _Repeat.weekly, label: Text('Every week')),
                  ButtonSegment(value: _Repeat.oneOff, label: Text('One day only')),
                ],
                selected: {repeat},
                onSelectionChanged: (s) => set(() => repeat = s.first),
              ),
              const SizedBox(height: 12),
              if (repeat == _Repeat.weekly)
                _WeekdayPicker(
                  selected: weekdays,
                  onToggled: (w) => set(() {
                    weekdays.contains(w)
                        ? weekdays.remove(w)
                        : weekdays.add(w);
                  }),
                  onPreset: (days) => set(() {
                    weekdays
                      ..clear()
                      ..addAll(days);
                  }),
                )
              else
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event),
                  title: Text(formatDateFull(date)),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime.now()
                          .subtract(const Duration(days: 1)),
                      lastDate:
                          DateTime.now().add(const Duration(days: 365)),
                    );
                    if (picked != null) set(() => date = dateOnly(picked));
                  },
                ),
              const SizedBox(height: 20),
              Row(children: [
                if (existing != null)
                  TextButton(
                    onPressed: () async {
                      await state.deleteBusySlot(existing.id);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('Delete'),
                  ),
                const Spacer(),
                FilledButton(
                  // The button reveals its own failure conditions: end after
                  // start, and — for weekly slots — at least one day picked.
                  // Otherwise a tap saved nothing and looked broken.
                  onPressed:
                      end > start && (repeat == _Repeat.oneOff || weekdays.isNotEmpty)
                          ? () async {
                              final labelText = label.text.trim().isEmpty
                                  ? 'Busy'
                                  : label.text.trim();
                              try {
                                // A weekly multi-day selection is fanned out
                                // into one slot per day — the storage model
                                // is one weekday per row, and this is the
                                // only place that translation happens.
                                if (repeat == _Repeat.oneOff) {
                                  await _saveOne(
                                    state: state,
                                    existing: existing,
                                    label: labelText,
                                    start: start,
                                    end: end,
                                    weekday: null,
                                    date: date,
                                  );
                                } else if (existing != null) {
                                  await _saveOne(
                                    state: state,
                                    existing: existing,
                                    label: labelText,
                                    start: start,
                                    end: end,
                                    weekday: weekdays.first,
                                    date: null,
                                  );
                                } else {
                                  for (final w in weekdays) {
                                    await state.addBusySlot(BusySlot(
                                      id: _slotId(),
                                      label: labelText,
                                      startMinute: start,
                                      endMinute: end,
                                      weekday: w,
                                    ));
                                  }
                                }
                                if (context.mounted) Navigator.pop(context);
                              } catch (e) {
                                // Every previous save silently swallowed its
                                // exception, which is how a broken migration
                                // went unreported. Surface it.
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Could not save: $e'),
                                      duration: const Duration(seconds: 6),
                                    ),
                                  );
                                }
                              }
                            }
                          : null,
                  child: const Text('Save'),
                ),
              ]),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ),
  );
}

String _slotId() =>
    'b${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

Future<void> _saveOne({
  required AppState state,
  required BusySlot? existing,
  required String label,
  required int start,
  required int end,
  required int? weekday,
  required DateTime? date,
}) async {
  final slot = BusySlot(
    id: existing?.id ?? _slotId(),
    label: label,
    startMinute: start,
    endMinute: end,
    weekday: weekday,
    date: date,
  );
  if (existing == null) {
    await state.addBusySlot(slot);
  } else {
    await state.updateBusySlot(slot);
  }
}

class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({
    required this.selected,
    required this.onToggled,
    required this.onPreset,
  });

  final Set<int> selected;
  final ValueChanged<int> onToggled;
  final ValueChanged<Set<int>> onPreset;

  static const _names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Days', style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 1; i <= 7; i++)
              GestureDetector(
                onTap: () => onToggled(i),
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected.contains(i)
                        ? theme.colorScheme.primary
                        : theme.colorScheme.surfaceContainerHighest,
                  ),
                  child: Text(
                    _names[i - 1],
                    style: TextStyle(
                      color: selected.contains(i)
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        // Two-tap presets for what a student actually wants — a college week
        // in one gesture rather than five.
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _Preset(
              label: 'Mon–Fri',
              onTap: () => onPreset({1, 2, 3, 4, 5}),
            ),
            _Preset(
              label: 'Weekends',
              onTap: () => onPreset({6, 7}),
            ),
            _Preset(
              label: 'Every day',
              onTap: () => onPreset({1, 2, 3, 4, 5, 6, 7}),
            ),
            _Preset(
              label: 'Clear',
              onTap: () => onPreset({}),
            ),
          ],
        ),
      ],
    );
  }
}

class _Preset extends StatelessWidget {
  const _Preset({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        textStyle: Theme.of(context).textTheme.bodySmall,
      ),
      child: Text(label),
    );
  }
}
