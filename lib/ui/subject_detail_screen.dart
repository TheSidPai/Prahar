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
                _SubjectStatus(subject: subject, topics: topics),
                const SizedBox(height: 8),
                for (final topic in topics) ...[
                  _TopicRow(topic: topic, subjectId: subjectId),
                  const SizedBox(height: 8),
                ],
              ],
            ),
    );
  }
}

/// The subject's standing, kept on screen while topics are being added.
///
/// The useful moment for "this needs 29 min/day" is while you are still
/// thinking about the subject. A dialog after each save would be the obvious
/// answer and the wrong one — topics get added a chapter at a time, and being
/// interrupted ten times running is worse than not being told. A panel that
/// updates in place says the same thing without ever getting in the way.
class _SubjectStatus extends StatelessWidget {
  const _SubjectStatus({required this.subject, required this.topics});

  final Subject subject;
  final List<Topic> topics;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = topics.fold(0, (a, t) => a + t.estimatedMinutes);
    final remaining = topics.fold(0, (a, t) => a + t.remainingMinutes);

    final exam = subject.examDate;
    final daysLeft =
        exam == null ? null : dateOnly(exam).difference(dateOnly(DateTime.now())).inDays;
    final perDay = (daysLeft != null && daysLeft > 0 && remaining > 0)
        ? (remaining / daysLeft).ceil()
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                _Stat(label: 'Topics', value: '${topics.length}'),
                const SizedBox(width: 28),
                _Stat(label: 'Left', value: formatMinutes(remaining)),
                const SizedBox(width: 28),
                _Stat(
                  label: 'Total',
                  value: formatMinutes(total),
                  muted: true,
                ),
              ]),
              if (perDay != null) ...[
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: RichText(
                    text: TextSpan(
                      style: theme.textTheme.bodyMedium,
                      children: [
                        const TextSpan(text: 'Needs '),
                        TextSpan(
                          text: formatMinutes(perDay),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        TextSpan(
                          text: ' a day to be ready by '
                              '${formatDate(dateOnly(exam!))}'
                              '  ·  $daysLeft days left',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              // An exam date is optional, but omitting it quietly parks the
              // subject at the bottom of every priority list forever. That is
              // too consequential to leave unsaid.
              if (exam == null) ...[
                const SizedBox(height: 16),
                _Nudge(
                  icon: Icons.event_busy_outlined,
                  text: 'No exam date, so this is scheduled only after '
                      'everything that has one. Add a date to give it '
                      'priority.',
                  onTap: () => showSubjectSheet(context, existing: subject),
                  action: 'Add date',
                ),
              ],
              if (daysLeft != null && daysLeft < 0) ...[
                const SizedBox(height: 16),
                _Nudge(
                  icon: Icons.history_toggle_off,
                  text: 'The exam date has passed, so nothing here is being '
                      'scheduled any more.',
                  onTap: () => showSubjectSheet(context, existing: subject),
                  action: 'Update',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.muted = false});

  final String label;
  final String value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: muted ? theme.colorScheme.onSurfaceVariant : null,
          ),
        ),
      ],
    );
  }
}

class _Nudge extends StatelessWidget {
  const _Nudge({
    required this.icon,
    required this.text,
    required this.onTap,
    required this.action,
  });

  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final String action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
          TextButton(onPressed: onTap, child: Text(action)),
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
                            if (!context.mounted) return;
                            Navigator.pop(context);

                            // Confirm what was actually committed to. The
                            // student typed pages; the plan runs on hours, and
                            // seeing the conversion once is what makes the
                            // estimate meaningful.
                            final unitLabel = switch (mode) {
                              EffortUnit.pages => '$amount pages',
                              EffortUnit.problems => '$amount problems',
                              EffortUnit.minutes => formatMinutes(amount),
                            };
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '$title — $unitLabel'
                                  '${mode == EffortUnit.minutes ? '' : ' ≈ ${formatMinutes(minutes)}'}',
                                ),
                                duration: const Duration(seconds: 4),
                              ),
                            );
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

