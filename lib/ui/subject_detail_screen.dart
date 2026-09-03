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
              '${formatMinutes(topic.estimatedMinutes)} · '
              'difficulty ${topic.difficulty}',
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
  final amountController = TextEditingController(
    text: existing == null ? '' : '${existing.estimatedMinutes}',
  );

  var difficulty = existing?.difficulty ?? 3;
  var mode = existing == null ? _EffortMode.pages : _EffortMode.minutes;
  const estimator = EffortEstimator.defaults;

  int? computeMinutes() {
    final raw = int.tryParse(amountController.text.trim());
    if (raw == null || raw <= 0) return null;
    return switch (mode) {
      _EffortMode.minutes => raw,
      _EffortMode.pages => (raw * estimator.minutesPerPage).round(),
      _EffortMode.problems => (raw * estimator.minutesPerProblem).round(),
    };
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
                SegmentedButton<_EffortMode>(
                  segments: const [
                    ButtonSegment(
                        value: _EffortMode.pages, label: Text('Pages')),
                    ButtonSegment(
                        value: _EffortMode.problems, label: Text('Problems')),
                    ButtonSegment(
                        value: _EffortMode.minutes, label: Text('Minutes')),
                  ],
                  selected: {mode},
                  // Convert the figure when the unit changes. Without this,
                  // switching Minutes -> Pages with "600" in the box silently
                  // reinterprets it as 600 pages and stores 1800 minutes: a
                  // 3x inflation with no warning.
                  onSelectionChanged: (s) => setState(() {
                    final next = s.first;
                    final current = computeMinutes();
                    mode = next;
                    if (current != null && current > 0) {
                      final converted = switch (next) {
                        _EffortMode.minutes => current,
                        _EffortMode.pages =>
                          (current / estimator.minutesPerPage).round(),
                        _EffortMode.problems =>
                          (current / estimator.minutesPerProblem).round(),
                      };
                      amountController.text = '${converted.clamp(1, 100000)}';
                    }
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
                      _EffortMode.pages => 'How many pages?',
                      _EffortMode.problems => 'How many problems?',
                      _EffortMode.minutes => 'How many minutes?',
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
                            if (existing == null) {
                              await state.addTopic(
                                subjectId: subjectId,
                                title: title,
                                estimatedMinutes: minutes,
                                difficulty: difficulty,
                              );
                            } else {
                              await state.updateTopic(existing.copyWith(
                                title: title,
                                estimatedMinutes: minutes,
                                difficulty: difficulty,
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

enum _EffortMode { pages, problems, minutes }
