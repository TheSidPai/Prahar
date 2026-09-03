import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/format.dart';
import '../domain/models.dart';
import '../state/app_state.dart';
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

class SubjectsScreen extends StatelessWidget {
  const SubjectsScreen({super.key});

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

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 90),
      children: [
        for (final subject in state.subjects)
          _SubjectRow(subject: subject, topics: state.topicsFor(subject.id)),
      ],
    );
  }
}

class _SubjectRow extends StatelessWidget {
  const _SubjectRow({required this.subject, required this.topics});

  final Subject subject;
  final List<Topic> topics;

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
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
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
                            'exam ${formatDate(subject.examDate!)}',
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
  var weight = existing?.weight ?? 3;
  var color = existing?.colorValue ?? subjectPalette.first;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
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
                        onPressed: () => setState(() => examDate = null),
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
                        weight: weight,
                        color: color,
                      );
                    } else {
                      await state.updateSubject(Subject(
                        id: existing.id,
                        name: name,
                        examDate: examDate,
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
  );
}
