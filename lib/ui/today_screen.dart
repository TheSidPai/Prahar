import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/format.dart';
import '../domain/schedule.dart';
import '../state/app_state.dart';
import '../domain/preferences.dart';
import 'brand.dart';
import 'glass.dart';
import 'how_it_works.dart';
import 'subjects_screen.dart';
import 'timer_screen.dart';
import 'widgets.dart';

class TodayScreen extends StatelessWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final theme = Theme.of(context);
    final sessions = state.todaySessions;

    // First run: explain the app rather than showing an empty page. Someone
    // who has just installed this has no idea what the five tabs are for.
    if (state.subjects.isEmpty) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          // The brand mark introduces the app on the one screen where a new
          // user genuinely sees it for the first time. Kept generous — a
          // 56px filled mark alongside the wordmark reads as a considered
          // welcome, not a login screen.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 8),
            child: PraharLogo(markSize: 56),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
            child: Text(
              'A study planner that tells you the truth about whether your '
              'plan is possible.',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const HowItWorks(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            child: FilledButton.icon(
              onPressed: () => showSubjectSheet(context),
              icon: const Icon(Icons.add),
              label: const Text('Add your first subject'),
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 90),
      children: [
        _Header(state: state),
        if (!state.batteryExempt) BatteryWarning(state: state),
        if (!state.exactAlarmsAllowed) const ExactAlarmWarning(),
        if (state.feasibility != null)
          FeasibilityBanner(feasibility: state.feasibility!),
        const SizedBox(height: 8),
        for (final entry in state.todayLog)
          LoggedTile(
            entry: entry,
            color: Color(
                state.subjectFor(entry.subjectId)?.colorValue ?? 0xFF4F46E5),
            onUndo: () async {
              await state.undoLogged(entry);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Undone — ${entry.topicTitle} is back'),
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            },
          ),
        if (sessions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                state.todayLog.isEmpty
                    ? 'No study time scheduled today.'
                    : "That's everything for today.",
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          )
        else
          for (final s in sessions)
            SessionTile(
              session: s,
              color: Color(
                  state.subjectFor(s.subjectId)?.colorValue ?? 0xFF4F46E5),
              isNow: _isNow(s),
              onStart: () => Navigator.push(
                context,
                MaterialPageRoute<int>(
                  builder: (_) => TimerScreen(session: s),
                ),
              ),
              onDone: () => confirmDone(context, state, s),
              onSkip: () => confirmSkip(context, state, s),
            ),
      ],
    );
  }

  /// Whether the clock is inside [s] right now.
  ///
  /// Read at build time rather than driven by a ticker: the pill is a marker,
  /// not a countdown, and a per-second rebuild of the whole list to move one
  /// chip is a poor trade. It refreshes on every state change and whenever
  /// the screen is rebuilt, which covers every moment a student is looking
  /// at it. The proper treatment of "the block happening now" is the hero
  /// card in the editorial Today redesign, not this.
  static bool _isNow(StudySession s) {
    final now = DateTime.now();
    final minute = now.hour * 60 + now.minute;
    return minute >= s.startMinuteOfDay &&
        minute < s.startMinuteOfDay + s.durationMinutes;
  }

}

class _Header extends StatelessWidget {
  const _Header({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = state.doneMinutesToday;
    final planned = state.plannedMinutesToday;
    final progress = planned == 0 ? 0.0 : (done / planned).clamp(0.0, 1.0);
    final glass = state.prefs.materialChoice == MaterialChoice.glass;

    // The header is the "hero surface" per the glass rule of one glass panel
    // per screen — wrapped when the material is glass, plain padding when
    // matte. Keeping both branches close together stops them drifting.
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDateFull(state.today),
                  style: theme.textTheme.titleLarge),
              // Amber: a streak is the one number here that is about effort
              // spent rather than time available.
              if (state.streak > 0)
                Row(children: [
                  Icon(Icons.local_fire_department,
                      size: 18, color: theme.colorScheme.tertiary),
                  const SizedBox(width: 4),
                  Text(
                    '${state.streak}',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(color: theme.colorScheme.tertiary),
                  ),
                ]),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: progress, minHeight: 8),
          ),
          const SizedBox(height: 6),
          Text(
            planned == 0
                ? 'Nothing planned today'
                : '${formatMinutes(done)} of ${formatMinutes(planned)}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      );

    if (!glass) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: content,
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: GlassSurface(
        borderRadius: BorderRadius.circular(20),
        padding: const EdgeInsets.all(18),
        child: content,
      ),
    );
  }
}
