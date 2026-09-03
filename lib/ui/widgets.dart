import 'package:flutter/material.dart';

import '../domain/format.dart';
import '../domain/schedule.dart';

/// The feasibility verdict, shown wherever a plan is shown.
///
/// Deliberately loud when the plan does not fit. A study app that quietly
/// generates an impossible schedule is worse than none at all — the student
/// only finds out the week of the exam.
class FeasibilityBanner extends StatelessWidget {
  const FeasibilityBanner({super.key, required this.feasibility});

  final Feasibility feasibility;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (feasibility.fits) {
      if (feasibility.requiredMinutes == 0) return const SizedBox.shrink();
      return _Card(
        color: theme.colorScheme.secondaryContainer,
        icon: Icons.check_circle_outline,
        title: 'The plan fits',
        lines: [
          '${formatMinutes(feasibility.requiredMinutes)} of work across '
              '${formatMinutes(feasibility.availableMinutes)} of study time.',
        ],
      );
    }

    return _Card(
      color: theme.colorScheme.errorContainer,
      icon: Icons.warning_amber_rounded,
      title: "This plan doesn't fit",
      lines: feasibility.warnings,
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.color,
    required this.icon,
    required this.title,
    required this.lines,
  });

  final Color color;
  final IconData icon;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(title, style: theme.textTheme.titleSmall),
          ]),
          const SizedBox(height: 6),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(line, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

class SessionTile extends StatelessWidget {
  const SessionTile({
    super.key,
    required this.session,
    required this.color,
    this.handled = false,
    this.onDone,
    this.onSkip,
  });

  final StudySession session;
  final Color color;
  final bool handled;
  final VoidCallback? onDone;
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Opacity(
      opacity: handled ? 0.45 : 1,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 42,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(
                        formatClock(session.startMinuteOfDay),
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatMinutes(session.durationMinutes),
                        style: theme.textTheme.bodySmall,
                      ),
                      if (session.isReview) ...[
                        const SizedBox(width: 8),
                        const _Chip(label: 'review'),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      session.topicTitle,
                      style: theme.textTheme.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      session.subjectName,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              // Labelled, not bare icons: a check and a clock face gave no
              // hint which was which, and one of them is irreversible.
              if (!handled && onSkip != null)
                TextButton(
                  onPressed: onSkip,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  child: const Text('Skip'),
                ),
              if (!handled && onDone != null)
                FilledButton.tonal(
                  onPressed: onDone,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Text('Done'),
                ),
              if (handled)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(Icons.check, size: 20),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A block that has already been dealt with. Rendered from the log rather than
/// the plan, so it stays put even though the planner no longer knows about it.
class LoggedTile extends StatelessWidget {
  const LoggedTile({super.key, required this.entry, required this.color});

  final LoggedSession entry;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Opacity(
      opacity: 0.5,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 38,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.topicTitle,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        decoration: TextDecoration.lineThrough,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      entry.wasSkipped
                          ? '${entry.subjectName} · skipped'
                          : '${entry.subjectName} · '
                              '${formatMinutes(entry.actualMinutes)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Icon(
                entry.wasSkipped ? Icons.redo : Icons.check_circle,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: theme.colorScheme.outline),
            const SizedBox(height: 14),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.outline),
            ),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      ),
    );
  }
}
