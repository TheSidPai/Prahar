import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/format.dart';
import '../domain/models.dart';
import '../state/app_state.dart';
import 'glass.dart';
import 'layout.dart';
import 'subject_detail_screen.dart';
import 'widgets.dart';

const subjectPalette = [
  0xFF4F46E5, // indigo
  0xFF0891B2, // cyan
  0xFF059669, // emerald
  0xFFD97706, // amber
  0xFFDC2626, // red
  0xFF7C3AED, // violet
  0xFFDB2777, // pink
];

class SubjectsScreen extends StatefulWidget {
  const SubjectsScreen({super.key});

  @override
  State<SubjectsScreen> createState() => _SubjectsScreenState();
}

class _SubjectsScreenState extends State<SubjectsScreen> {
  String _query = '';
  bool _showArchive = false;

  /// The subject shown in the right-hand pane when there is room for one.
  /// Null means "nothing chosen yet"; the pane then falls back to the first
  /// subject in the list, so the screen is never half empty on arrival.
  String? _selected;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();

    if (state.subjects.isEmpty) {
      return EmptyState(
        icon: Icons.library_books_outlined,
        title: 'No subjects',
        message: 'Start with one subject and its exam date.',
        action: FilledButton.icon(
          onPressed: () => showSubjectSheet(context),
          icon: const Icon(Icons.add),
          label: const Text('Add subject'),
        ),
      );
    }

    final q = _query.trim().toLowerCase();
    bool matches(Subject s) {
      if (q.isEmpty) return true;
      if (s.name.toLowerCase().contains(q)) return true;
      return state.topicsFor(s.id).any(
            (t) => t.title.toLowerCase().contains(q),
          );
    }

    final active = state.activeSubjects.where(matches).toList();
    final archived = state.archivedSubjects.where(matches).toList();

    // With a query on, every matched topic is also shown so a search across
    // topics is genuinely useful — otherwise "chapter 4" would only surface
    // the subject and not the row you were looking for.
    final matchedTopics = q.isEmpty
        ? const <Topic>[]
        : state.topics
            .where((t) => t.title.toLowerCase().contains(q))
            .toList();

    // Two panes when there is width: the list stops being a menu you leave in
    // order to look at something, and becomes an index you read alongside it.
    final wide = Layout.isWide(MediaQuery.sizeOf(context));
    final shown = _selected ?? (active.isNotEmpty ? active.first.id : null);

    final list = ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 90),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: _SearchField(
            value: _query,
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        for (final subject in active)
          _SubjectRow(
            subject: subject,
            topics: state.topicsFor(subject.id),
            selected: wide && subject.id == shown,
            onTap: wide ? () => setState(() => _selected = subject.id) : null,
          ),

        if (q.isNotEmpty && matchedTopics.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            child: Text(
              'MATCHED TOPICS',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                    letterSpacing: 1.0,
                  ),
            ),
          ),
          for (final t in matchedTopics)
            _TopicHit(topic: t, state: state),
        ],

        if (archived.isNotEmpty) ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Archive · ${archived.length}',
                  style: Theme.of(context).textTheme.titleSmall),
              subtitle: const Text('Subjects whose exam has passed'),
              trailing: Icon(_showArchive ? Icons.expand_less : Icons.expand_more),
              onTap: () => setState(() => _showArchive = !_showArchive),
            ),
          ),
          if (_showArchive)
            for (final s in archived)
              _SubjectRow(
                subject: s,
                topics: state.topicsFor(s.id),
                selected: wide && s.id == shown,
                onTap: wide ? () => setState(() => _selected = s.id) : null,
              ),
        ],
      ],
    );

    if (!wide) return list;

    return Row(
      children: [
        Expanded(flex: 4, child: list),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 6,
          child: shown == null
              ? const EmptyState(
                  icon: Icons.library_books_outlined,
                  title: 'Pick a subject',
                  message: 'Its topics and standing appear here.',
                )
              : _DetailPane(subjectId: shown),
        ),
      ],
    );
  }
}

/// The right-hand pane: the subject's own page, minus the page.
///
/// It carries its own small header because there is no app bar out here to
/// hold the name, the edit action or the way to add a topic — the FAB belongs
/// to the Subjects tab and adds *subjects*.
class _DetailPane extends StatelessWidget {
  const _DetailPane({required this.subjectId});

  final String subjectId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subject = context.select<AppState, Subject?>(
        (s) => s.subjectFor(subjectId));
    if (subject == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Color(subject.colorValue),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  subject.name,
                  style: theme.textTheme.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: 'Edit subject',
                icon: const Icon(Icons.edit_outlined, size: 20),
                onPressed: () => showSubjectSheet(context, existing: subject),
              ),
              TextButton.icon(
                onPressed: () =>
                    showTopicSheet(context, subjectId: subject.id),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Topic'),
              ),
            ],
          ),
        ),
        Expanded(child: SubjectDetailBody(subjectId: subject.id)),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search subjects or topics',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: value.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => onChanged(''),
              ),
        // Compact so the field does not shove content down.
        isDense: true,
      ),
    );
  }
}

class _TopicHit extends StatelessWidget {
  const _TopicHit({required this.topic, required this.state});

  final Topic topic;
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final subject = state.subjectFor(topic.subjectId);
    if (subject == null) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: ListTile(
          leading: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Color(subject.colorValue),
              shape: BoxShape.circle,
            ),
          ),
          title: Text(topic.title, style: theme.textTheme.bodyLarge),
          subtitle: Text(subject.name, style: theme.textTheme.bodySmall),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => SubjectDetailScreen(subjectId: subject.id),
            ),
          ),
        ),
      ),
    );
  }
}

class _SubjectRow extends StatelessWidget {
  const _SubjectRow({
    required this.subject,
    required this.topics,
    this.selected = false,
    this.onTap,
  });

  final Subject subject;
  final List<Topic> topics;

  /// Marked as the one showing in the detail pane. Only ever true in the
  /// two-pane layout, where a list row and a pane are on screen together and
  /// the link between them has to be visible.
  final bool selected;

  /// Overrides the default "push the detail page" tap, which is what the
  /// two-pane layout does instead of navigating.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = topics.fold(0, (a, t) => a + t.remainingMinutes);

    // Two states that do nothing and say nothing. A subject with no topics
    // contributes no work at all, and one with no exam date sits at the bottom
    // of every priority list permanently. Both are easy to create by accident
    // and impossible to notice.
    final needsTopics = topics.isEmpty;
    final needsDate = subject.examDate == null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Card(
        // The selected row borrows the accent for its edge rather than a fill:
        // a filled row in a list of cards reads as a different kind of thing,
        // and it is the same subject either way.
        shape: selected
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.colorScheme.tertiary, width: 1.5),
              )
            : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap ??
              () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SubjectDetailScreen(subjectId: subject.id),
                    ),
                  ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Color(subject.colorValue),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(subject.name, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (!needsTopics) '${topics.length} topics',
                          if (!needsTopics) '${formatMinutes(remaining)} left',
                          if (subject.examDate != null)
                            'exam ${formatDate(subject.examDate!)}'
                                '${subject.examMinuteOfDay == null ? '' : ' '
                                    '${formatClock(subject.examMinuteOfDay!)}'}',
                        ].join('  ·  '),
                        style: theme.textTheme.bodySmall,
                      ),
                      if (needsTopics || needsDate) ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          Icon(Icons.error_outline,
                              size: 14, color: theme.colorScheme.tertiary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              needsTopics
                                  ? 'No topics yet — nothing is being scheduled'
                                  : 'No exam date — scheduled last',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.tertiary,
                              ),
                            ),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 20, color: theme.colorScheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Add or edit a subject. Exam date is optional but heavily encouraged — it is
/// what drives every urgency decision the planner makes.
Future<void> showSubjectSheet(BuildContext context, {Subject? existing}) async {
  final state = context.read<AppState>();
  final nameController = TextEditingController(text: existing?.name ?? '');
  var examDate = existing?.examDate;
  var examMinute = existing?.examMinuteOfDay;
  var weight = existing?.weight ?? 3;
  var color = existing?.colorValue ?? subjectPalette.first;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SheetBackground(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (context, setState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(existing == null ? 'New subject' : 'Edit subject',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                autofocus: existing == null,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Subject',
                  hintText: 'Organic Chemistry',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(examDate == null
                    ? 'No exam date'
                    : 'Exam ${formatDateFull(examDate!)}'),
                subtitle: const Text('Drives how urgently this is scheduled'),
                trailing: examDate == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setState(() {
                          examDate = null;
                          examMinute = null;
                        }),
                      ),
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: examDate ??
                        now.add(const Duration(days: 30)),
                    firstDate: now,
                    lastDate: now.add(const Duration(days: 730)),
                  );
                  if (picked != null) setState(() => examDate = picked);
                },
              ),
              // The time is optional and only offered once a date exists —
              // a start time without a day is meaningless. Setting it stops
              // the exam day from counting as a whole day of preparation,
              // which is the whole reason it is here, so the row says so.
              if (examDate != null)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_outlined),
                  title: Text(examMinute == null
                      ? 'Time not set'
                      : 'Starts at ${formatClock(examMinute!)}'),
                  subtitle: Text(examMinute == null
                      ? 'The whole day counts as preparation time'
                      : 'Only the hours before it count as preparation'),
                  trailing: examMinute == null
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () => setState(() => examMinute = null),
                        ),
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: examMinute == null
                          ? const TimeOfDay(hour: 9, minute: 0)
                          : TimeOfDay(
                              hour: examMinute! ~/ 60,
                              minute: examMinute! % 60,
                            ),
                    );
                    if (picked != null) {
                      setState(() => examMinute = picked.hour * 60 + picked.minute);
                    }
                  },
                ),
              // Said before saving, not after: the consequence of omitting a
              // date is invisible once the sheet closes.
              if (examDate == null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .tertiaryContainer
                        .withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Without a date this subject is scheduled only after '
                        'every subject that has one.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ]),
                ),
              const SizedBox(height: 12),
              Text('Importance', style: Theme.of(context).textTheme.labelLarge),
              Slider(
                value: weight.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                label: '$weight',
                onChanged: (v) => setState(() => weight = v.round()),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                children: [
                  for (final c in subjectPalette)
                    GestureDetector(
                      onTap: () => setState(() => color = c),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: color == c
                              ? Border.all(width: 3, color: Colors.black54)
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(children: [
                if (existing != null)
                  TextButton(
                    onPressed: () async {
                      await state.deleteSubject(existing.id);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('Delete'),
                  ),
                const Spacer(),
                FilledButton(
                  onPressed: () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;
                    if (existing == null) {
                      await state.addSubject(
                        name: name,
                        examDate: examDate,
                        examMinuteOfDay: examMinute,
                        weight: weight,
                        color: color,
                      );
                    } else {
                      await state.updateSubject(Subject(
                        id: existing.id,
                        name: name,
                        examDate: examDate,
                        examMinuteOfDay: examMinute,
                        weight: weight,
                        colorValue: color,
                      ));
                    }
                    if (context.mounted) Navigator.pop(context);
                  },
                  child: const Text('Save'),
                ),
              ]),
              const SizedBox(height: 8),
            ],
          ),
          ),
        ),
      ),
    ),
  );
}
