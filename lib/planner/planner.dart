import 'dart:math';

import '../domain/format.dart';
import '../domain/models.dart';
import '../domain/schedule.dart';

/// Tunables. Defaults are deliberately conservative — 50-minute blocks with
/// 10-minute breaks, no more than two consecutive blocks of one subject.
class PlannerConfig {
  final int maxSessionMinutes;
  final int minSessionMinutes;
  final int breakMinutes;

  /// Interleaving beats blocking for retention, so cap how many blocks of the
  /// same subject may run back to back.
  final int maxConsecutiveSameSubject;

  /// Earliest clock time a session may start, in minutes since midnight.
  final int dayStartMinute;

  /// Latest clock time a session may *end*. Without this, a generous daily
  /// availability plus a late replan happily schedules study past midnight.
  final int dayEndMinute;

  /// Days after first completion at which reviews are scheduled.
  final List<int> reviewOffsetDays;

  final int reviewMinutes;

  /// Ceiling on the share of a day reviews may take before new material gets
  /// the rest. Reviews are placed first because they are time-critical, but
  /// four rungs per finished topic accumulate fast, and without a ceiling a
  /// student with a busy backlog would spend every session revising and never
  /// cover anything new.
  final double reviewShareOfDay;

  /// How many times more pressed a subject must be before it is allowed to
  /// ignore the interleaving cap.
  final double urgencyOverrideRatio;

  /// How far ahead to plan when no exam date bounds the work.
  final int horizonDays;

  const PlannerConfig({
    this.maxSessionMinutes = 50,
    this.minSessionMinutes = 20,
    this.breakMinutes = 10,
    this.maxConsecutiveSameSubject = 2,
    this.dayStartMinute = 6 * 60,
    this.dayEndMinute = 22 * 60,
    this.reviewOffsetDays = const [1, 3, 7, 21],
    this.reviewMinutes = 15,
    this.reviewShareOfDay = 0.4,
    this.urgencyOverrideRatio = 3.0,
    this.horizonDays = 180,
  });
}

class _PendingReview {
  final String topicId;
  final DateTime due;
  const _PendingReview(this.topicId, this.due);
}

/// Builds a day-by-day schedule.
///
/// Deliberately greedy rather than an optimiser. Three reasons:
///  * it runs in microseconds, so replanning on every change is free;
///  * its output is *explainable* — you can always say why a block landed where
///    it did, which matters when a student asks;
///  * it is stable. Re-running after one missed session shifts that work
///    forward instead of reshuffling the whole month, which an optimiser
///    would happily do.
///
/// Reach for OR-Tools only if these schedules turn out to be genuinely bad.
class Planner {
  final PlannerConfig config;

  const Planner({this.config = const PlannerConfig()});

  Plan generate({
    required List<Subject> subjects,
    required List<Topic> topics,
    required Availability availability,
    required DateTime today,

    /// Earliest minute-of-day to place work on the *first* day only.
    ///
    /// Callers pass the current clock time so that replanning at 3pm does not
    /// offer blocks starting at 6am. Later days always start at
    /// [PlannerConfig.dayStartMinute].
    int? todayStartMinute,
  }) {
    final start = dateOnly(today);
    final subjectById = {for (final s in subjects) s.id: s};
    final topicById = {for (final t in topics) t.id: t};

    // Remaining work, in minutes, keyed by topic.
    //
    // Work behind an exam that has already happened is left out entirely.
    // The day loop would refuse to schedule it anyway, so it used to fall
    // through to the feasibility pass as "unscheduled" and report the plan
    // impossible — permanently, and for a subject nothing can be done about.
    // A finished exam is not a shortfall; it is over.
    final work = <String, int>{};
    for (final t in topics) {
      if (t.isDone || t.remainingMinutes <= 0) continue;
      if (!_withinDeadline(subjectById[t.subjectId], start)) continue;
      work[t.id] = t.remainingMinutes;
    }

    // Prerequisites already satisfied before planning starts.
    final satisfied = <String>{
      for (final t in topics)
        if (t.isDone) t.id,
    };

    // Outstanding minutes per subject, kept in step with [work] so that
    // scheduling pressure falls as a subject gets covered.
    final remainingBySubject = <String, int>{};
    for (final entry in work.entries) {
      final t = topicById[entry.key];
      if (t == null) continue;
      remainingBySubject.update(
        t.subjectId,
        (v) => v + entry.value,
        ifAbsent: () => entry.value,
      );
    }

    final horizonEnd = _horizonEnd(subjects, start);
    final requiredMinutes = work.values.fold(0, (a, b) => a + b);
    final availableMinutes = availability.totalBetween(start, horizonEnd);

    final sessions = <StudySession>[];
    final pendingReviews = <_PendingReview>[];

    // Reviews owed for topics finished before this plan was generated.
    for (final t in topics) {
      if (t.isDone && t.firstCompletedOn != null) {
        _queueReviews(pendingReviews, t.id, dateOnly(t.firstCompletedOn!),
            notBefore: start);
      }
    }

    // Stepping via the DateTime constructor rather than `add(Duration(days: 1))`
    // keeps every iteration on local midnight. Adding 24 hours drifts off
    // midnight across a DST boundary, which would make two iterations land on
    // the same calendar date.
    for (var day = start;
        !day.isAfter(horizonEnd);
        day = DateTime(day.year, day.month, day.day + 1)) {
      var capacity = availability.minutesOn(day);
      if (capacity <= 0) continue;

      // Two independent limits, and both must hold. The free intervals say
      // *where* a block may go — the window minus lectures, lunch, a shift.
      // The minute budget says *how much* the student intends to do, which is
      // usually far less than the time they are technically free.
      final earliest = (day == start && todayStartMinute != null)
          ? max(config.dayStartMinute, todayStartMinute)
          : config.dayStartMinute;

      final intervals = availability
          .freeIntervals(
            day,
            windowStart: config.dayStartMinute,
            windowEnd: config.dayEndMinute,
          )
          .where((r) => r.$2 > earliest)
          .map((r) => (r.$1 < earliest ? earliest : r.$1, r.$2))
          .toList();
      if (intervals.isEmpty) continue;

      var slot = 0;
      var cursor = intervals.first.$1;

      /// Moves to the next interval when the current one is full. Returns
      /// false when the day is exhausted.
      bool advance(int need) {
        while (slot < intervals.length) {
          if (cursor < intervals[slot].$1) cursor = intervals[slot].$1;
          if (cursor + need <= intervals[slot].$2) return true;
          slot++;
          if (slot < intervals.length) cursor = intervals[slot].$1;
        }
        return false;
      }

      final placed = <String>[]; // subject ids, in the order placed today

      // Subjects whose exam has already started by the time the cursor
      // reaches them. Only ever non-empty on an exam day with a known exam
      // time, and only for the rest of that day — the rest of the board
      // carries on filling the afternoon.
      final examOver = <String>{};

      // 1. Reviews due today go first. They are short and time-critical: a
      //    review done three days late is barely a review at all.
      final dueToday = pendingReviews
          .where((r) => !r.due.isAfter(day))
          .toList()
        ..sort((a, b) => a.due.compareTo(b.due));

      var reviewBudget = (capacity * config.reviewShareOfDay).floor();

      for (final r in dueToday) {
        if (reviewBudget < config.reviewMinutes) break;
        if (capacity < config.reviewMinutes) break;
        if (!advance(config.reviewMinutes)) break;
        final topic = topicById[r.topicId];
        if (topic == null) {
          pendingReviews.remove(r);
          continue;
        }
        final subject = subjectById[topic.subjectId];
        if (!_withinDeadline(subject, day)) {
          pendingReviews.remove(r);
          continue;
        }
        // A review after the exam has started helps nobody. Leave it queued:
        // the topic may belong to a later exam too, and dropping it here
        // would silently lose the rung.
        if (!_fitsBeforeExam(subject, day, cursor, config.reviewMinutes)) {
          continue;
        }

        sessions.add(StudySession(
          id: _sessionId('r', day, cursor, topic.id),
          topicId: topic.id,
          subjectId: topic.subjectId,
          topicTitle: topic.title,
          subjectName: subject?.name ?? '',
          date: day,
          startMinuteOfDay: cursor,
          durationMinutes: config.reviewMinutes,
          kind: SessionKind.review,
        ));

        pendingReviews.remove(r);
        capacity -= config.reviewMinutes;
        reviewBudget -= config.reviewMinutes;
        cursor += config.reviewMinutes + config.breakMinutes;
        placed.add(topic.subjectId);
      }

      // 2. Fill the rest of the day with new material.
      while (capacity >= config.minSessionMinutes && work.isNotEmpty) {
        final topic = _pickNext(
          work: work,
          topicById: topicById,
          subjectById: subjectById,
          remainingBySubject: remainingBySubject,
          satisfied: satisfied,
          day: day,
          placed: placed,
          cursor: cursor,
          minimumBlock: config.minSessionMinutes,
          examOver: examOver,
        );
        if (topic == null) break;

        // The current free interval bounds the block just as much as the
        // student's stated capacity does.
        if (!advance(config.minSessionMinutes)) break;
        final roomLeft = intervals[slot].$2 - cursor;
        var usable = min(capacity, roomLeft);

        // On the exam day the block must also finish before the exam starts.
        // The pick happened at the old cursor, so this is re-checked here:
        // advance() may have skipped a busy slot and landed past the exam.
        // Retiring just this subject for the day, rather than ending the day,
        // leaves the afternoon available to everything else.
        final cutoff = _cutoffMinute(subjectById[topic.subjectId], day);
        if (cutoff != null) {
          if (cursor + config.minSessionMinutes > cutoff) {
            examOver.add(topic.subjectId);
            continue;
          }
          usable = min(usable, cutoff - cursor);
        }

        final remaining = work[topic.id]!;
        var duration = min(config.maxSessionMinutes, remaining);
        if (duration > usable) duration = usable;

        // Avoid leaving a useless sliver behind. Shrinking this block so the
        // remainder clears the minimum beats either emitting a 5-minute
        // fragment later or overrunning the block length now.
        final left = remaining - duration;
        if (left > 0 && left < config.minSessionMinutes) {
          final rebalanced = remaining - config.minSessionMinutes;
          if (rebalanced >= config.minSessionMinutes && rebalanced <= usable) {
            duration = rebalanced;
          } else if (remaining <= usable &&
              remaining <= config.maxSessionMinutes) {
            duration = remaining;
          }
        }

        final subject = subjectById[topic.subjectId];
        sessions.add(StudySession(
          id: _sessionId('n', day, cursor, topic.id),
          topicId: topic.id,
          subjectId: topic.subjectId,
          topicTitle: topic.title,
          subjectName: subject?.name ?? '',
          date: day,
          startMinuteOfDay: cursor,
          durationMinutes: duration,
          kind: SessionKind.newMaterial,
        ));

        remainingBySubject.update(
          topic.subjectId,
          (v) => max(0, v - duration),
          ifAbsent: () => 0,
        );

        final now = remaining - duration;
        if (now <= 0) {
          work.remove(topic.id);
          satisfied.add(topic.id);
          _queueReviews(pendingReviews, topic.id, day, notBefore: start);
        } else {
          work[topic.id] = now;
        }

        capacity -= duration;
        cursor += duration + config.breakMinutes;
        placed.add(topic.subjectId);
      }

      if (work.isEmpty && pendingReviews.isEmpty) break;
    }

    return Plan(
      sessions: sessions,
      feasibility: _assess(
        leftover: work,
        topicById: topicById,
        subjectById: subjectById,
        requiredMinutes: requiredMinutes,
        availableMinutes: availableMinutes,
        start: start,
        horizonEnd: horizonEnd,
      ),
      generatedAt: today,
    );
  }

  // ---------------------------------------------------------------- internals

  /// Content-addressed session id.
  ///
  /// Must not be a running counter: plans are regenerated constantly, and a
  /// sequential id would refer to a different block after every replan, so
  /// anything that remembered "session 3 is done" would silently point at the
  /// wrong block. Day + start minute + topic is unique within a plan and
  /// stable across regenerations.
  String _sessionId(String prefix, DateTime day, int startMinute, String topicId) =>
      '$prefix|${dateKey(day)}|$startMinute|$topicId';

  /// Queues the spaced-repetition ladder for [topicId].
  ///
  /// Rungs that already fell due before [notBefore] are dropped rather than
  /// piled onto day one — a student returning to a topic finished last month
  /// should not be handed four overdue reviews in one sitting.
  void _queueReviews(
    List<_PendingReview> queue,
    String topicId,
    DateTime completedOn, {
    required DateTime notBefore,
  }) {
    for (final offset in config.reviewOffsetDays) {
      // Constructor arithmetic, not Duration — see the day loop.
      final due =
          DateTime(completedOn.year, completedOn.month, completedOn.day + offset);
      if (due.isBefore(notBefore)) continue;
      queue.add(_PendingReview(topicId, due));
    }
  }

  DateTime _horizonEnd(List<Subject> subjects, DateTime start) {
    final byDays = start.add(Duration(days: config.horizonDays));
    final exams = subjects
        .map((s) => s.examDate)
        .whereType<DateTime>()
        .map(dateOnly)
        .toList();
    if (exams.isEmpty) return byDays;

    final latest = exams.reduce((a, b) => a.isAfter(b) ? a : b);
    // Undated subjects still need room beyond the last exam.
    final hasUndated = subjects.any((s) => s.examDate == null);
    if (hasUndated) return latest.isAfter(byDays) ? latest : byDays;
    return latest.isBefore(start) ? start : latest;
  }

  /// Work for a subject is pointless after its exam.
  bool _withinDeadline(Subject? subject, DateTime day) {
    final exam = subject?.examDate;
    if (exam == null) return true;
    return !day.isAfter(dateOnly(exam));
  }

  /// Latest minute of [day] at which work for [subject] is still worth doing.
  ///
  /// Only the exam day itself is bounded, and only when the exam time is
  /// known: revising Physics at 11am for a Physics exam that started at 9am
  /// is not preparation, it is a scheduling bug. Null means unbounded.
  int? _cutoffMinute(Subject? subject, DateTime day) {
    final exam = subject?.examDate;
    final minute = subject?.examMinuteOfDay;
    if (exam == null || minute == null) return null;
    return day == dateOnly(exam) ? minute : null;
  }

  /// Whether a block of [need] minutes starting at [cursor] finishes in time
  /// to be useful to [subject] on [day].
  bool _fitsBeforeExam(Subject? subject, DateTime day, int cursor, int need) {
    final cutoff = _cutoffMinute(subject, day);
    return cutoff == null || cursor + need <= cutoff;
  }

  /// Scheduling pressure: the minutes per day this subject still demands.
  ///
  /// This is the critical-ratio (least-slack) heuristic, and it is deliberately
  /// *workload-aware*. An earlier version scored purely on `1 / daysToExam`,
  /// which is wrong in a way that matters:
  ///
  ///   Subject A — exam in 60 days, 100 hours left → needs 100 min/day
  ///   Subject B — exam in 30 days,   2 hours left → needs   4 min/day
  ///
  /// Deadline-only scoring ranks B twice as urgent as A, and the student
  /// discovers the problem with A far too late. Dividing the *remaining work*
  /// by the days available ranks them 25:1 the other way, which is the honest
  /// answer.
  ///
  /// Weight is the student's stated importance; difficulty applies a mild
  /// ±10%-per-step nudge rather than dominating.
  double _priority(
    Topic topic,
    Subject? subject,
    DateTime day,
    Map<String, int> remainingBySubject,
  ) {
    // The exam day counts for whatever part of it precedes the exam: a whole
    // day when only the date is known, a sliver when the paper starts at 9am.
    // The floor keeps the ratio finite on the morning of an exam, where the
    // subject genuinely is the most pressed thing on the board.
    final prepDays = subject?.prepDaysFrom(
      day,
      windowStartMinute: config.dayStartMinute,
      windowEndMinute: config.dayEndMinute,
    );
    final daysLeft = prepDays == null ? 365.0 : max(0.1, prepDays);

    final subjectRemaining =
        remainingBySubject[topic.subjectId] ?? topic.remainingMinutes;
    final requiredRate = subjectRemaining / daysLeft;

    final weight = subject?.weight ?? 3;
    final difficultyFactor = 1 + (topic.difficulty - 3) * 0.1;

    return requiredRate * weight * difficultyFactor;
  }

  int _trailingRun(List<String> placed, String subjectId) {
    var n = 0;
    for (var i = placed.length - 1; i >= 0; i--) {
      if (placed[i] == subjectId) {
        n++;
      } else {
        break;
      }
    }
    return n;
  }

  Topic? _pickNext({
    required Map<String, int> work,
    required Map<String, Topic> topicById,
    required Map<String, Subject> subjectById,
    required Map<String, int> remainingBySubject,
    required Set<String> satisfied,
    required DateTime day,
    required List<String> placed,

    /// Where in the day the next block would start. Only matters on an exam
    /// day with a known exam time, where a subject stops being schedulable
    /// part-way through the day rather than at midnight.
    required int cursor,
    required int minimumBlock,

    /// Subjects already retired for the day because their exam has started.
    required Set<String> examOver,
  }) {
    // Best candidate that respects the interleaving cap.
    Topic? best;
    var bestScore = double.negativeInfinity;

    // Best candidate ignoring the cap. Serves two purposes: it stops the day
    // stalling when every ready topic is capped out, and it lets a subject in
    // genuine crisis override interleaving entirely.
    Topic? uncapped;
    var uncappedScore = double.negativeInfinity;

    for (final id in work.keys) {
      final topic = topicById[id];
      if (topic == null) continue;

      if (examOver.contains(topic.subjectId)) continue;

      final subject = subjectById[topic.subjectId];
      if (!_withinDeadline(subject, day)) continue;
      if (!_fitsBeforeExam(subject, day, cursor, minimumBlock)) continue;

      // A prerequisite that doesn't exist can't be waited on — treat it as met
      // rather than deadlocking the whole plan on a typo.
      final blocked = topic.prerequisiteIds.any(
        (p) => topicById.containsKey(p) && !satisfied.contains(p),
      );
      if (blocked) continue;

      final score = _priority(topic, subject, day, remainingBySubject);

      if (score > uncappedScore) {
        uncapped = topic;
        uncappedScore = score;
      }

      if (_trailingRun(placed, topic.subjectId) >=
          config.maxConsecutiveSameSubject) {
        continue;
      }
      if (score > bestScore) {
        best = topic;
        bestScore = score;
      }
    }

    if (best == null) return uncapped;

    // Interleaving aids retention, but not at any price. When one subject is
    // dramatically more pressed than anything else available — an exam in three
    // days against one in three months — forcing a token block of the relaxed
    // subject into the day is the wrong trade.
    if (uncapped != null &&
        uncappedScore > bestScore * config.urgencyOverrideRatio) {
      return uncapped;
    }
    return best;
  }

  Feasibility _assess({
    required Map<String, int> leftover,
    required Map<String, Topic> topicById,
    required Map<String, Subject> subjectById,
    required int requiredMinutes,
    required int availableMinutes,
    required DateTime start,
    required DateTime horizonEnd,
  }) {
    final unscheduled = leftover.values.fold(0, (a, b) => a + b);
    final warnings = <String>[];

    if (unscheduled > 0) {
      // Group the shortfall by subject — "you're short 6h" is far less useful
      // than "Physics won't fit before the 20th".
      final bySubject = <String, int>{};
      for (final entry in leftover.entries) {
        final topic = topicById[entry.key];
        if (topic == null) continue;
        bySubject.update(
          topic.subjectId,
          (v) => v + entry.value,
          ifAbsent: () => entry.value,
        );
      }

      final ordered = bySubject.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      for (final entry in ordered) {
        final subject = subjectById[entry.key];
        final name = subject?.name ?? 'Unknown subject';
        final exam = subject?.examDate;
        warnings.add(exam == null
            ? '$name: ${formatMinutes(entry.value)} of work has nowhere to go.'
            : "$name: ${formatMinutes(entry.value)} won't fit before "
                '${formatDate(dateOnly(exam))}.');
      }

      final days = horizonEnd.difference(start).inDays + 1;
      final perDay = (unscheduled / days).ceil();
      warnings.add('Short by ${formatMinutes(unscheduled)} overall — '
          'add about ${formatMinutes(perDay)} a day, or cut scope.');

      final blocked = leftover.keys.where((id) {
        final t = topicById[id];
        if (t == null) return false;
        return t.prerequisiteIds
            .any((p) => topicById.containsKey(p) && leftover.containsKey(p));
      }).length;
      if (blocked > 0 && blocked == leftover.length) {
        warnings.add(
            'Every unscheduled topic is waiting on a prerequisite — check for '
            'a cycle in your prerequisites.');
      }
    }

    return Feasibility(
      requiredMinutes: requiredMinutes,
      availableMinutes: availableMinutes,
      unscheduledMinutes: unscheduled,
      warnings: warnings,
    );
  }
}
