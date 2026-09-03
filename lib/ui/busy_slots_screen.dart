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
          ? EmptyState(
              icon: Icons.event_busy_outlined,
              title: 'No busy slots',
              message: 'Add class hours, lunch, a shift — anything the schedule '
                  'should route around. Weekly repeats or a single date.',
              action: FilledButton.icon(
                onPressed: () => _showSheet(context),
                icon: const Icon(Icons.add),
                label: const Text('Add a slot'),
              ),
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
  var weekday = existing?.weekday ?? DateTime.now().weekday;
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
                    selected: weekday, onChanged: (w) => set(() => weekday = w))
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
                  onPressed: end > start
                      ? () async {
                          final slot = BusySlot(
                            id: existing?.id ?? _slotId(),
                            label: label.text.trim().isEmpty
                                ? 'Busy'
                                : label.text.trim(),
                            startMinute: start,
                            endMinute: end,
                            weekday: repeat == _Repeat.weekly ? weekday : null,
                            date: repeat == _Repeat.oneOff ? date : null,
                          );
                          if (existing == null) {
                            await state.addBusySlot(slot);
                          } else {
                            await state.updateBusySlot(slot);
                          }
                          if (context.mounted) Navigator.pop(context);
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

class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  static const _names = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (var i = 1; i <= 7; i++)
          GestureDetector(
            onTap: () => onChanged(i),
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == selected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
              child: Text(
                _names[i - 1],
                style: TextStyle(
                  color: i == selected
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
