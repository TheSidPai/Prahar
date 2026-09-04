import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/format.dart';
import '../domain/models.dart';
import '../domain/preferences.dart';
import '../domain/schedule.dart';
import '../state/app_state.dart';
import 'glass.dart';
import 'theme.dart';

/// Skipping costs the slot as well as the block: the time is subtracted from
/// today, so the work rolls to a later day rather than being offered again in
/// the hours that are left. That second consequence is invisible, so the
/// dialog says it before the tap rather than after.
///
/// It does *not* claim to be irreversible — it once did, which was simply
/// untrue: a skipped block appears in today's list with an Undo button like
/// any other logged one, and [AppState.undoLogged] removes it.
Future<void> confirmSkip(
    BuildContext context, AppState state, StudySession session) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Skip this block?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(session.topicTitle,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 12),
          Text(
            'The work moves to a later day, and today loses '
            '${formatMinutes(session.durationMinutes)} of study time, so it '
            "won't be offered again today.",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          Text(
            'You can undo it from today’s list.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep it'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Skip'),
        ),
      ],
    ),
  );
  if (ok == true) await state.markSkipped(session);
}

/// Asks for the *actual* time spent rather than assuming the plan was
/// followed. That single number is what keeps future estimates honest.
///
/// The study timer measures the same number instead of asking for it, which
/// is strictly better evidence — this dialog remains for blocks done away
/// from the app.
Future<void> confirmDone(
    BuildContext context, AppState state, StudySession session) async {
  var minutes = session.durationMinutes;

  final result = await showDialog<int>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('How long did it take?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(session.topicTitle),
            const SizedBox(height: 16),
            Text(formatMinutes(minutes),
                style: Theme.of(context).textTheme.headlineSmall),
            Slider(
              value: minutes.toDouble(),
              min: 5,
              max: 180,
              divisions: 35,
              onChanged: (v) => setState(() => minutes = v.round()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, minutes),
            child: const Text('Log it'),
          ),
        ],
      ),
    ),
  );

  if (result != null) {
    await state.markDone(session, actualMinutes: result);
  }
}

/// The single most important warning in the app.
///
/// Without a battery-optimisation exemption Android freezes the process, and a
/// perfectly registered exact alarm wakes nothing. The reminder then appears
/// only when the app is next opened by hand — which is exactly when it is
/// worthless. Confirmed on a Xiaomi device: identical code, exemption off,
/// nothing arrived; exemption on, it arrived to the minute.
///
/// Lives here rather than on one screen because both Today screens need it,
/// and a warning this important must not exist in two versions that can drift.
class BatteryWarning extends StatelessWidget {
  const BatteryWarning({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.battery_alert, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Reminders will not arrive',
                  style: theme.textTheme.titleSmall),
            ),
          ]),
          const SizedBox(height: 6),
          Text(
            'Android is allowed to freeze Prahar in the background, so study '
            'reminders will only appear when you open the app yourself. Allow '
            'it to run unrestricted and they arrive on time.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () async {
                final ok = await state.requestBatteryExemption();
                if (context.mounted && !ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Still restricted. Settings > Apps > Prahar > Battery '
                        '> No restrictions, and turn on Autostart.',
                      ),
                      duration: Duration(seconds: 8),
                    ),
                  );
                }
              },
              child: const Text('Fix this'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Android 12+ silently downgrades alarms to inexact ones unless the user
/// grants this. A 6pm reminder arriving at 7:20pm is how a study app loses a
/// student's trust, so it gets called out rather than failing quietly.
class ExactAlarmWarning extends StatelessWidget {
  const ExactAlarmWarning({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        const Icon(Icons.alarm_off, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Exact alarms are off, so reminders may arrive late. Enable '
            '"Alarms & reminders" for Prahar in Android settings.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      ]),
    );
  }
}

/// The deadline in the fewest words that are still true.
///
/// Null when the subject has no exam date. Once a time is known it is worth
/// saying on the last two days, when "today" and "tomorrow" are the difference
/// between an evening of revision and none.
String? examLabel(Subject s, DateTime today) {
  final exam = s.examDate;
  if (exam == null) return null;
  final days = dateOnly(exam).difference(dateOnly(today)).inDays;
  if (days < 0) return 'exam passed';

  final at = s.examMinuteOfDay;
  final clock = at == null ? '' : ' at ${formatClock(at)}';
  if (days == 0) return 'exam today$clock';
  if (days == 1) return 'exam tomorrow$clock';
  return '$days days left';
}

/// The feasibility verdict, shown wherever a plan is shown.
///
/// Deliberately loud when the plan does not fit. A study app that quietly
/// generates an impossible schedule is worse than none at all — the student
/// only finds out the week of the exam.
class FeasibilityBanner extends StatelessWidget {
  const FeasibilityBanner({
    super.key,
    required this.feasibility,
    this.condensed = false,
  });

  final Feasibility feasibility;

  /// Shrinks the *passing* verdict to a single line. A whole panel spent
  /// saying "everything is fine" is the most expensive reassurance on the
  /// screen. The failing verdict is never condensed — being blunt about an
  /// impossible plan is the single most valuable thing this app does, and the
  /// student only finds out otherwise in the week of the exam.
  final bool condensed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (feasibility.fits) {
      if (feasibility.requiredMinutes == 0) return const SizedBox.shrink();

      final summary = '${formatMinutes(feasibility.requiredMinutes)} of work '
          'across ${formatMinutes(feasibility.availableMinutes)} of study time.';

      if (condensed) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 2, 20, 0),
          child: Row(children: [
            Icon(Icons.check_circle_outline,
                size: 14, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text('The plan fits · $summary',
                  style: theme.textTheme.bodySmall),
            ),
          ]),
        );
      }

      return _Card(
        color: theme.colorScheme.secondaryContainer,
        icon: Icons.check_circle_outline,
        title: 'The plan fits',
        lines: [summary],
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
    final glass = context.select<AppState, MaterialChoice>(
            (s) => s.prefs.materialChoice) ==
        MaterialChoice.glass;
    final radius = BorderRadius.circular(14);

    final content = Column(
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
    );

    if (!glass) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color, borderRadius: radius),
        child: content,
      );
    }

    // The verdict is the one panel on Today that must not read as another
    // card in the list, so it gets glass. The tint keeps its semantic colour
    // — warm for "fits", error for "doesn't" — at an alpha low enough that
    // the blur is still doing the work.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: GlassSurface(
        borderRadius: radius,
        padding: const EdgeInsets.all(14),
        tint: color.withValues(alpha: 0.45),
        child: SizedBox(width: double.infinity, child: content),
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
    this.isNow = false,
    this.onDone,
    this.onSkip,
    this.onStart,
  });

  final StudySession session;
  final Color color;
  final bool handled;

  /// Whether the clock is currently inside this block. Marks the one tile
  /// that is about the present rather than the plan — the same thing the
  /// home-screen widget calls NOW, in the same colour.
  final bool isNow;

  final VoidCallback? onDone;
  final VoidCallback? onSkip;

  /// Opens the focus timer for this block. The whole tile is the target —
  /// there is no room for a third button beside Skip and Done, and a tile you
  /// can tap is a more forgiving target than an icon anyway.
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final inner = Padding(
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
                      if (isNow) ...[
                        const SizedBox(width: 8),
                        const _Chip(label: 'now', accented: true),
                      ],
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
                  // The theme paints every FilledButton in full amber, and
                  // one FilledButtonThemeData serves the tonal variant too.
                  // A tile carries one of these per block, so it asks for the
                  // quiet half of the accent family back explicitly.
                  style: FilledButton.styleFrom(
                    backgroundColor: theme.colorScheme.secondaryContainer,
                    foregroundColor: theme.colorScheme.onSecondaryContainer,
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
        );

    return Opacity(
      opacity: handled ? 0.45 : 1,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        clipBehavior: Clip.antiAlias,
        child: onStart == null
            ? inner
            : InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onStart,
                child: inner,
              ),
      ),
    );
  }
}

/// A block that has already been dealt with. Rendered from the log rather than
/// the plan, so it stays put even though the planner no longer knows about it.
class LoggedTile extends StatelessWidget {
  const LoggedTile({
    super.key,
    required this.entry,
    required this.color,
    this.onUndo,
  });

  final LoggedSession entry;
  final Color color;

  /// Marking done and skipping were both irreversible, so one mis-tap
  /// permanently corrupted progress. Undo is the cheapest possible remedy.
  final VoidCallback? onUndo;

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
              if (onUndo != null)
                TextButton(
                  onPressed: onUndo,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Undo'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, this.accented = false});

  final String label;

  /// Full-strength amber rather than the quiet container. Reserved for "now":
  /// a chip that means *the present moment* has to out-rank one that merely
  /// classifies the block.
  final bool accented;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color:
            accented ? PraharTheme.accent : theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: accented
            ? theme.textTheme.labelSmall?.copyWith(
                color: PraharTheme.accentInk,
                fontWeight: FontWeight.w700,
              )
            : theme.textTheme.labelSmall,
      ),
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
