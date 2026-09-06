import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/format.dart';
import '../domain/models.dart';
import '../domain/schedule.dart';
import '../state/app_state.dart';
import 'glass.dart';
import 'layout.dart';
import 'timer_screen.dart';
import 'widgets.dart';

/// The week, in whichever direction the screen has room for.
///
/// Seven columns and a clock down the side is the right drawing of a week, and
/// it needs width. A phone has 411dp: minus a clock gutter that is 52dp a
/// column, which is a colour and not a word, and the first attempt looked
/// exactly like that — a wall of hour lines with unlabelled chips in it.
///
/// So upright the axes turn over. Days become rows and time runs left to
/// right, which hands each day the full width instead of a seventh of it, and
/// makes room for the one thing the grid could never fit: what the block
/// actually is. Sideways, where the width is real, the grid is still the
/// better drawing and is what Plan shows beside the month.
///
/// Both read the plan and nothing else. Sessions already carry a date, a start
/// minute and a length; nothing here is stored.
class WeekScreen extends StatefulWidget {
  const WeekScreen({super.key});

  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> {
  /// Weeks forward from the seven days beginning today. Never negative: the
  /// past is not planned, and empty columns are not history.
  int _offset = 0;

  /// The expanded day in the upright layout. Today to begin with, because the
  /// question on opening is almost always "what is left of today".
  String? _open;

  static const _hourHeight = 56.0;
  static const _gutter = 44.0;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final plan = state.plan;

    if (plan == null || plan.sessions.isEmpty) {
      return const EmptyState(
        icon: Icons.calendar_view_week_outlined,
        title: 'No schedule yet',
        message: 'Add subjects and topics, and the week fills in.',
      );
    }

    final windowStart = state.prefs.dayStartMinute;
    final windowEnd = state.prefs.dayEndMinute;
    if (windowEnd <= windowStart) {
      return const EmptyState(
        icon: Icons.schedule,
        title: 'No study window',
        message: 'Set a start and end time under Settings > Study time.',
      );
    }

    // Seven days from today, not Monday to Sunday.
    //
    // A calendar week is the wrong frame for a planner: opened on a Saturday
    // it spends five of its seven columns on days that have already happened
    // and can never be filled. Rolling from today, every day shown is a day
    // something can still be done about. Calendar arithmetic throughout —
    // adding Duration(days:) lands an hour early across a DST boundary.
    final today = state.today;
    final first = DateTime(
      today.year,
      today.month,
      today.day + _offset * 7,
    );
    final days = [
      for (var i = 0; i < 7; i++)
        DateTime(first.year, first.month, first.day + i),
    ];

    final lastPlanned = plan.sessions
        .map((s) => s.date)
        .reduce((a, b) => a.isAfter(b) ? a : b);

    final header = _RangeHeader(
      days: days,
      onPrevious: _offset > 0 ? () => setState(() => _offset--) : null,
      onNext: days.last.isBefore(lastPlanned)
          ? () => setState(() => _offset++)
          : null,
    );

    if (Layout.isWide(MediaQuery.sizeOf(context))) {
      return _WeekColumns(
        state: state,
        days: days,
        today: today,
        header: header,
        windowStart: windowStart,
        windowEnd: windowEnd,
        hourHeight: _hourHeight,
        gutter: _gutter,
      );
    }

    return _WeekRows(
      state: state,
      days: days,
      today: today,
      header: header,
      windowStart: windowStart,
      windowEnd: windowEnd,
      openKey: _open ?? dateKey(today),
      onOpen: (key) => setState(() => _open = key),
    );
  }
}

/// Which seven days, and the way to the next seven.
class _RangeHeader extends StatelessWidget {
  const _RangeHeader({
    required this.days,
    required this.onPrevious,
    required this.onNext,
  });

  final List<DateTime> days;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous week',
          icon: const Icon(Icons.chevron_left),
          onPressed: onPrevious,
        ),
        Expanded(
          child: Text(
            '${formatDate(days.first)} – ${formatDate(days.last)}',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        IconButton(
          tooltip: 'Next week',
          icon: const Icon(Icons.chevron_right),
          onPressed: onNext,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Upright: a row per day, time running across.
// ---------------------------------------------------------------------------

class _WeekRows extends StatelessWidget {
  const _WeekRows({
    required this.state,
    required this.days,
    required this.today,
    required this.header,
    required this.windowStart,
    required this.windowEnd,
    required this.openKey,
    required this.onOpen,
  });

  final AppState state;
  final List<DateTime> days;
  final DateTime today;
  final Widget header;
  final int windowStart;
  final int windowEnd;
  final String openKey;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView(
      // 90 for the navigation bar, which the body runs under when the material
      // is glass. The legend lived below this list on the first attempt and
      // was drawn underneath the nav where nobody could see it.
      padding: EdgeInsets.only(
        top: glassTopInset(context),
        bottom: navBottomInset(context),
      ),
      children: [
        header,
        _HourAxis(windowStart: windowStart, windowEnd: windowEnd),
        for (final day in days)
          _DayRow(
            day: day,
            isToday: dateKey(day) == dateKey(today),
            isOpen: dateKey(day) == openKey,
            sessions: state.plan!.onDate(day),
            busy: state.availability.busy
                .where((b) => b.appliesTo(day))
                .toList(),
            windowStart: windowStart,
            windowEnd: windowEnd,
            colourOf: (id) =>
                Color(state.subjectFor(id)?.colorValue ?? 0xFF4F46E5),
            onOpen: () => onOpen(dateKey(day)),
          ),
        _Legend(state: state),
      ],
    );
  }
}

/// The times the tracks below are drawn against, labelled once at the top
/// rather than repeated on every row.
class _HourAxis extends StatelessWidget {
  const _HourAxis({required this.windowStart, required this.windowEnd});

  final int windowStart;
  final int windowEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final span = windowEnd - windowStart;

    // Every third hour: enough to orient by, few enough that the labels do not
    // collide at 360dp of track.
    final marks = <int>[];
    for (var h = (windowStart / 60).ceil(); h * 60 <= windowEnd; h++) {
      if (h % 3 == 0) marks.add(h);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(_DayRow.labelWidth + 16, 2, 16, 2),
      child: SizedBox(
        height: 14,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            clipBehavior: Clip.none,
            children: [
              for (final h in marks)
                Positioned(
                  left:
                      (h * 60 - windowStart) / span * constraints.maxWidth - 14,
                  child: Text(
                    formatClock(h * 60),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                      fontSize: 10,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One day: a label, a track of the day's shape, and — when opened — what the
/// blocks on it actually are.
class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.isToday,
    required this.isOpen,
    required this.sessions,
    required this.busy,
    required this.windowStart,
    required this.windowEnd,
    required this.colourOf,
    required this.onOpen,
  });

  final DateTime day;
  final bool isToday;
  final bool isOpen;
  final List<StudySession> sessions;
  final List<BusySlot> busy;
  final int windowStart;
  final int windowEnd;
  final Color Function(String subjectId) colourOf;
  final VoidCallback onOpen;

  /// Room for "Wed" over "10" at labelMedium, and no more — the rest of the
  /// width belongs to the track.
  static const labelWidth = 40.0;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = sessions.fold(0, (a, s) => a + s.durationMinutes);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: labelWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _weekdays[day.weekday - 1],
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isToday
                                  ? theme.colorScheme.tertiary
                                  : theme.colorScheme.outline,
                            ),
                          ),
                          Text(
                            '${day.day}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: isToday ? FontWeight.w700 : null,
                              color: isToday
                                  ? theme.colorScheme.tertiary
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: _Track(
                        sessions: sessions,
                        busy: busy,
                        windowStart: windowStart,
                        windowEnd: windowEnd,
                        colourOf: colourOf,
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 44,
                      child: Text(
                        total == 0 ? '—' : formatMinutes(total),
                        textAlign: TextAlign.right,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),

                // Opening a day is how the names get on screen at all. The
                // track says where the work sits; this says what it is.
                if (isOpen) ...[
                  const SizedBox(height: 6),
                  const Divider(height: 1),
                  if (sessions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        busy.isEmpty
                            ? 'Nothing scheduled.'
                            : 'Nothing scheduled — the day is spoken for.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline,
                        ),
                      ),
                    )
                  else
                    for (final s in sessions)
                      _BlockLine(
                        session: s,
                        colour: colourOf(s.subjectId),
                        // Only today's blocks open the timer: tapping a future
                        // block would log work that has not happened.
                        onTap: isToday
                            ? () => Navigator.push(
                                context,
                                MaterialPageRoute<int>(
                                  builder: (_) => TimerScreen(session: s),
                                ),
                              )
                            : null,
                      ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A day's shape at a glance: where the work sits, and what is blocked out.
class _Track extends StatelessWidget {
  const _Track({
    required this.sessions,
    required this.busy,
    required this.windowStart,
    required this.windowEnd,
    required this.colourOf,
  });

  final List<StudySession> sessions;
  final List<BusySlot> busy;
  final int windowStart;
  final int windowEnd;
  final Color Function(String subjectId) colourOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final span = windowEnd - windowStart;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        double x(int minute) =>
            (minute.clamp(windowStart, windowEnd) - windowStart) / span * width;

        return SizedBox(
          height: 26,
          child: Stack(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const SizedBox.expand(),
              ),

              // Behind the blocks, because this is why the gaps are shaped the
              // way they are rather than content in its own right.
              for (final b in busy)
                if (b.endMinute > windowStart && b.startMinute < windowEnd)
                  Positioned(
                    left: x(b.startMinute),
                    width: (x(b.endMinute) - x(b.startMinute)).clamp(
                      2.0,
                      double.infinity,
                    ),
                    top: 0,
                    bottom: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.16,
                        ),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),

              for (final s in sessions)
                Positioned(
                  left: x(s.startMinuteOfDay),
                  // A 25-minute block is 4dp at this scale, which is a line
                  // rather than a bar; the floor keeps it visible without
                  // making it lie about its length by much.
                  width: (x(s.endMinuteOfDay) - x(s.startMinuteOfDay)).clamp(
                    5.0,
                    double.infinity,
                  ),
                  top: 3,
                  bottom: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colourOf(s.subjectId).withValues(
                        alpha: s.status == SessionStatus.done ? 0.4 : 0.95,
                      ),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// One block, named. This is the line the grid had no room for.
class _BlockLine extends StatelessWidget {
  const _BlockLine({
    required this.session,
    required this.colour,
    required this.onTap,
  });

  final StudySession session;
  final Color colour;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = session.status == SessionStatus.done;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 26,
              decoration: BoxDecoration(
                color: colour,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            // The subject and topic are the one string the app does not
            // control, so they get the width and the clock is pinned right.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session.topicTitle.isEmpty
                        ? session.subjectName
                        : session.topicTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      decoration: done ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text(
                    session.isReview
                        ? '${session.subjectName} · review'
                        : session.subjectName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${formatClock(session.startMinuteOfDay)}'
              '–${formatClock(session.endMinuteOfDay)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (onTap != null)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.play_arrow_rounded, size: 18),
              ),
          ],
        ),
      ),
    );
  }
}

/// What the colours mean, grey included.
class _Legend extends StatelessWidget {
  const _Legend({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subjects = state.activeSubjects;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
      child: Wrap(
        spacing: 14,
        runSpacing: 6,
        children: [
          for (final s in subjects)
            _Swatch(colour: Color(s.colorValue), label: s.name, theme: theme),
          // The grey bands are the question every one of these views raises,
          // and the only one the drawing cannot answer by itself.
          _Swatch(
            colour: theme.colorScheme.onSurface.withValues(alpha: 0.16),
            label: 'Busy',
            theme: theme,
          ),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.colour,
    required this.label,
    required this.theme,
  });

  final Color colour;
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Sideways: seven columns and a clock, which is what the width is for.
// ---------------------------------------------------------------------------

class _WeekColumns extends StatelessWidget {
  const _WeekColumns({
    required this.state,
    required this.days,
    required this.today,
    required this.header,
    required this.windowStart,
    required this.windowEnd,
    required this.hourHeight,
    required this.gutter,
  });

  final AppState state;
  final List<DateTime> days;
  final DateTime today;
  final Widget header;
  final int windowStart;
  final int windowEnd;
  final double hourHeight;
  final double gutter;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final span = windowEnd - windowStart;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.only(top: glassTopInset(context)),
          child: Column(
            children: [
              header,
              Row(
                children: [
                  SizedBox(width: gutter),
                  for (final day in days)
                    Expanded(
                      child: _ColumnHeading(
                        letter: _letters[day.weekday - 1],
                        number: day.day,
                        isToday: dateKey(day) == dateKey(today),
                      ),
                    ),
                ],
              ),
              const Divider(height: 1),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: SizedBox(
              height: span / 60 * hourHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ClockGutter(
                    windowStart: windowStart,
                    windowEnd: windowEnd,
                    hourHeight: hourHeight,
                    width: gutter,
                  ),
                  for (final day in days)
                    Expanded(
                      child: _DayColumn(
                        isToday: dateKey(day) == dateKey(today),
                        sessions: state.plan!.onDate(day),
                        busy: state.availability.busy
                            .where((b) => b.appliesTo(day))
                            .toList(),
                        windowStart: windowStart,
                        windowEnd: windowEnd,
                        hourHeight: hourHeight,
                        colourOf: (id) => Color(
                          state.subjectFor(id)?.colorValue ?? 0xFF4F46E5,
                        ),
                        onTap: (session) => Navigator.push(
                          context,
                          MaterialPageRoute<int>(
                            builder: (_) => TimerScreen(session: session),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(color: theme.colorScheme.surface),
          child: _Legend(state: state),
        ),
      ],
    );
  }
}

class _ColumnHeading extends StatelessWidget {
  const _ColumnHeading({
    required this.letter,
    required this.number,
    required this.isToday,
  });

  final String letter;
  final int number;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.tertiary;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          Text(
            letter,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isToday ? accent : theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: isToday
                ? BoxDecoration(color: accent, shape: BoxShape.circle)
                : null,
            child: Text(
              '$number',
              style: theme.textTheme.labelMedium?.copyWith(
                color: isToday ? theme.colorScheme.onTertiary : null,
                fontWeight: isToday ? FontWeight.w600 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ClockGutter extends StatelessWidget {
  const _ClockGutter({
    required this.windowStart,
    required this.windowEnd,
    required this.hourHeight,
    required this.width,
  });

  final int windowStart;
  final int windowEnd;
  final double hourHeight;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstHour = (windowStart / 60).ceil();
    final lastHour = windowEnd ~/ 60;

    return SizedBox(
      width: width,
      child: Stack(
        children: [
          for (var h = firstHour; h <= lastHour; h++)
            Positioned(
              top: (h * 60 - windowStart) / 60 * hourHeight - 7,
              right: 6,
              child: Text(
                formatClock(h * 60),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.isToday,
    required this.sessions,
    required this.busy,
    required this.windowStart,
    required this.windowEnd,
    required this.hourHeight,
    required this.colourOf,
    required this.onTap,
  });

  final bool isToday;
  final List<StudySession> sessions;
  final List<BusySlot> busy;
  final int windowStart;
  final int windowEnd;
  final double hourHeight;
  final Color Function(String subjectId) colourOf;
  final void Function(StudySession) onTap;

  double _dy(int minute) =>
      (minute.clamp(windowStart, windowEnd) - windowStart) / 60 * hourHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstHour = (windowStart / 60).ceil();
    final lastHour = windowEnd ~/ 60;

    return LayoutBuilder(
      builder: (context, constraints) {
        final roomForText = constraints.maxWidth >= 74;

        return DecoratedBox(
          decoration: BoxDecoration(
            color: isToday
                ? theme.colorScheme.primary.withValues(alpha: 0.04)
                : null,
            border: Border(
              left: BorderSide(color: theme.dividerColor, width: 0.5),
            ),
          ),
          child: Stack(
            children: [
              for (var h = firstHour; h <= lastHour; h++)
                Positioned(
                  top: _dy(h * 60),
                  left: 0,
                  right: 0,
                  child: Divider(height: 1, color: theme.dividerColor),
                ),

              for (final b in busy)
                if (b.endMinute > windowStart && b.startMinute < windowEnd)
                  Positioned(
                    top: _dy(b.startMinute),
                    height: _dy(b.endMinute) - _dy(b.startMinute),
                    left: 0,
                    right: 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.10,
                        ),
                      ),
                    ),
                  ),

              for (final s in sessions)
                Positioned(
                  top: _dy(s.startMinuteOfDay),
                  height: (_dy(s.endMinuteOfDay) - _dy(s.startMinuteOfDay))
                      .clamp(14.0, double.infinity),
                  left: 1,
                  right: 1,
                  child: _ColumnBlock(
                    session: s,
                    colour: colourOf(s.subjectId),
                    showText: roomForText,
                    onTap: isToday ? () => onTap(s) : null,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ColumnBlock extends StatelessWidget {
  const _ColumnBlock({
    required this.session,
    required this.colour,
    required this.showText,
    required this.onTap,
  });

  final StudySession session;
  final Color colour;
  final bool showText;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final done = session.status == SessionStatus.done;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: colour.withValues(alpha: done ? 0.16 : 0.34),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border(left: BorderSide(color: colour, width: 2.5)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: showText
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.subjectName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                      Text(
                        formatClock(session.startMinuteOfDay),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  )
                : const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}
