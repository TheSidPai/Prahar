import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../domain/format.dart';
import '../domain/models.dart';
import '../planner/estimator.dart';
import '../state/app_state.dart';
import 'subjects_screen.dart';
import 'widgets.dart';

class SubjectDetailScreen extends StatelessWidget {
  const SubjectDetailScreen({super.key, required this.subjectId});

  final String subjectId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final subject = state.subjectFor(subjectId);
    if (subject == null) return const Scaffold(body: SizedBox.shrink());

    final topics = state.topicsFor(subjectId);
    final remaining = topics.fold(0, (a, t) => a + t.remainingMinutes);

    return Scaffold(
      appBar: AppBar(
        title: Text(subject.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => showSubjectSheet(context, existing: subject),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showTopicSheet(context, subjectId: subjectId),
        icon: const Icon(Icons.add),
        label: const Text('Topic'),
      ),
      body: topics.isEmpty
          ? const EmptyState(
              icon: Icons.topic_outlined,
              title: 'No topics',
              message:
                  'Break the syllabus into topics. Chapters work well — small '
                  'enough to finish in a session or two.',
            )
          : ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 90),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(
                    '${topics.length} topics · ${formatMinutes(remaining)} remaining',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                for (final topic in topics)
                  _TopicRow(topic: topic, subjectId: subjectId),
              ],
            ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  const _TopicRow({required this.topic, required this.subjectId});

  final Topic topic;
  final String subjectId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        title: Text(
          topic.title,
          style: TextStyle(
            decoration: topic.isDone ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              '${formatMinutes(topic.completedMinutes)} / '
              '${formatMinutes(topic.estimatedMinutes)}'
              '${topic.estimateUnit == EffortUnit.minutes ? '' : '  (${topic.estimateLabel})'}'
              ' · difficulty ${topic.difficulty}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: topic.progress.clamp(0.0, 1.0),
                minHeight: 5,
              ),
            ),
          ],
        ),
        trailing: const Icon(Icons.more_vert),
        onTap: () =>
            showTopicSheet(context, subjectId: subjectId, existing: topic),
      ),
    );
  }
}

/// Add or edit a topic.
///
/// The effort field defaults to counting *pages*, not minutes. Students cannot
/// estimate minutes but can read a page count off a book, and the estimator
/// converts at a rate that later calibrates itself from real sessions.
Future<void> showTopicSheet(
  BuildContext context, {
  required String subjectId,
  Topic? existing,
}) async {
  final state = context.read<AppState>();
  final titleController = TextEditingController(text: existing?.title ?? '');

  // Reopen a topic in the unit it was entered in, showing the figure that was
  // typed. Previously this always showed derived minutes, so "200 pages" came
  // back as "600" under a Minutes label.
  final amountController = TextEditingController(
    text: existing == null ? '' : '${existing.estimateAmount}',
  );

  var difficulty = existing?.difficulty ?? 3;
  var mode = existing?.estimateUnit ?? EffortUnit.pages;
  const estimator = EffortEstimator.defaults;

  int? amountEntered() {
    final raw = int.tryParse(amountController.text.trim());
    if (raw == null || raw <= 0) return null;
    return raw;
  }

  int? computeMinutes() {
    final raw = amountEntered();
    if (raw == null) return null;
    return (raw * estimator.rateFor(mode)).round();
  }

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: StatefulBuilder(
        builder: (context, setState) {
          final minutes = computeMinutes();
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(existing == null ? 'New topic' : 'Edit topic',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 16),
                TextField(
                  controller: titleController,
                  autofocus: existing == null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Topic',
                    hintText: 'Ch. 4 — Aldehydes and Ketones',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<EffortUnit>(
                  segments: const [
                    ButtonSegment(
                        value: EffortUnit.pages, label: Text('Pages')),
                    ButtonSegment(
                        value: EffortUnit.problems, label: Text('Problems')),
                    ButtonSegment(
                        value: EffortUnit.minutes, label: Text('Minutes')),
                  ],
                  selected: {mode},
                  // Convert the figure when the unit changes. Without this,
                  // switching Minutes -> Pages with "600" in the box silently
                  // reinterprets it as 600 pages and stores 1800 minutes: a
                  // 3x inflation with no warning.
                  onSelectionChanged: (s) => setState(() {
                    final next = s.first;
                    final current = amountEntered();
                    if (current != null) {
                      amountController.text =
                          '${estimator.convert(current, mode, next)}';
                    }
                    mode = next;
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: switch (mode) {
                      EffortUnit.pages => 'How many pages?',
                      EffortUnit.problems => 'How many problems?',
                      EffortUnit.minutes => 'How many minutes?',
                    },
                    border: const OutlineInputBorder(),
                    helperText: minutes == null
                        ? null
                        : 'Estimated at ${formatMinutes(minutes)}',
                  ),
                ),
                const SizedBox(height: 12),
                Text('Difficulty',
                    style: Theme.of(context).textTheme.labelLarge),
                Slider(
                  value: difficulty.toDouble(),
                  min: 1,
                  max: 5,
                  divisions: 4,
                  label: '$difficulty',
                  onChanged: (v) => setState(() => difficulty = v.round()),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  if (existing != null)
                    TextButton(
                      onPressed: () async {
                        await state.deleteTopic(existing.id);
                        if (context.mounted) Navigator.pop(context);
                      },
                      child: const Text('Delete'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: minutes == null ||
                            titleController.text.trim().isEmpty
                        ? null
                        : () async {
                            final title = titleController.text.trim();
                            final amount = amountEntered()!;
                            final rate = estimator.rateFor(mode);
                            if (existing == null) {
                              await state.addTopic(
                                subjectId: subjectId,
                                title: title,
                                unit: mode,
                                amount: amount,
                                rate: rate,
                                difficulty: difficulty,
                              );
                            } else {
                              await state.updateTopic(existing.copyWith(
                                title: title,
                                estimatedMinutes: minutes,
                                difficulty: difficulty,
                                estimateUnit: mode,
                                estimateAmount: amount,
                                estimateRate: rate,
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
          );
        },
      ),
    ),
  );
}

