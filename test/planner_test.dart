import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/domain/models.dart';
import 'package:prahar/domain/schedule.dart';
import 'package:prahar/planner/planner.dart';

/// Fixed "today" so no test depends on the wall clock.
final today = DateTime(2026, 9, 3);

Subject subject(String id, {DateTime? exam, int? examMinute, int weight = 3}) =>
    Subject(
      id: id,
      name: id,
      examDate: exam,
      examMinuteOfDay: examMinute,
      weight: weight,
    );

Topic topic(
  String id,
  String subjectId,
  int minutes, {
  int difficulty = 3,
  List<String> prereqs = const [],
  int done = 0,
  TopicStatus status = TopicStatus.notStarted,
  DateTime? completedOn,
}) =>
    Topic(
      id: id,
      subjectId: subjectId,
      title: id,
      estimatedMinutes: minutes,
      completedMinutes: done,
      difficulty: difficulty,
      prerequisiteIds: prereqs,
      status: status,
      firstCompletedOn: completedOn,
    );

/// Same number of minutes every day of the week.
Availability flat(int minutes) => Availability(minutesByWeekday: {
      for (var d = 1; d <= 7; d++) d: minutes,
    });

void main() {
  const planner = Planner();

  group('capacity', () {
    test('never schedules more than a day allows', () {
      final plan = planner.generate(
        subjects: [subject('phys'), subject('math')],
        topics: [topic('a', 'phys', 600), topic('b', 'math', 600)],
        availability: flat(100),
        today: today,
      );

      expect(plan.sessions, isNotEmpty);
      for (var d = today;
          d.isBefore(today.add(const Duration(days: 30)));
          d = d.add(const Duration(days: 1))) {
        expect(plan.minutesOn(d), lessThanOrEqualTo(100),
            reason: 'overbooked ${d.toIso8601String()}');
      }
    });

    test('respects zero-availability days', () {
      final holiday = today.add(const Duration(days: 2));
      final plan = planner.generate(
        subjects: [subject('phys')],
        topics: [topic('a', 'phys', 600)],
        availability: flat(100).withOverride(holiday, 0),
        today: today,
      );

      expect(plan.onDate(holiday), isEmpty);
      expect(plan.sessions, isNotEmpty);
    });

    test('schedules nothing before today', () {
      final plan = planner.generate(
        subjects: [subject('phys')],
        topics: [topic('a', 'phys', 300)],
        availability: flat(100),
        today: today,
      );

      for (final s in plan.sessions) {
        expect(s.date.isBefore(today), isFalse);
      }
    });
  });

  group('busy slots', () {
    BusySlot slot(int start, int end, {int? weekday, DateTime? date}) =>
        BusySlot(
          id: '$start-$end',
          label: 'busy',
          startMinute: start,
          endMinute: end,
          weekday: weekday,
          date: date,
        );

    test('no block is scheduled during a busy slot', () {
      final busy = flat(300).withBusy([slot(13 * 60, 15 * 60, weekday: 4)]);
      final plan = planner.generate(
        subjects: [subject('phys')],
        topics: [topic('a', 'phys', 300)],
        availability: busy,
        today: today,
      );

      for (final s in plan.onDate(today)) {
        // Nothing may overlap 13:00-15:00.
        expect(
          s.endMinuteOfDay <= 13 * 60 || s.startMinuteOfDay >= 15 * 60,
          isTrue,
          reason: 'scheduled ${s.startMinuteOfDay}-${s.endMinuteOfDay} '
              'across a busy slot',
        );
      }
    });

    test('a one-off slot applies only to its date', () {
      final busy = flat(300).withBusy([slot(6 * 60, 22 * 60, date: today)]);
      final plan = planner.generate(
        subjects: [subject('phys')],
        topics: [topic('a', 'phys', 300)],
        availability: busy,
        today: today,
      );

      expect(plan.onDate(today), isEmpty,
          reason: 'today is entirely busy');
      expect(plan.onDate(today.add(const Duration(days: 1))), isNotEmpty,
          reason: 'the one-off must not affect other days');
    });

    test('overlapping slots are merged before subtracting', () {
      // "class" 09:00-13:00 and "lab" 11:00-12:00 must not re-open a gap.
      final busy = flat(300).withBusy([
        slot(9 * 60, 13 * 60, weekday: 4),
        slot(11 * 60, 12 * 60, weekday: 4),
      ]);
      final plan = planner.generate(
        subjects: [subject('phys')],
        topics: [topic('a', 'phys', 300)],
        availability: busy,
        today: today,
      );

      for (final s in plan.onDate(today)) {
        // The whole 09:00-13:00 window must remain blocked.
        expect(
          s.endMinuteOfDay <= 9 * 60 || s.startMinuteOfDay >= 13 * 60,
          isTrue,
          reason: 'block landed inside a merged busy window',
        );
      }
    });

    test('minute budget still limits work when free time is abundant', () {
      // Free intervals decide *where*, minutes decide *how much*. Even with a
      // huge window, only 60 minutes may be spent.
      final busy = Availability(minutesByWeekday: {
        for (var d = 1; d <= 7; d++) d: 60,
      }).withBusy([slot(12 * 60, 13 * 60, weekday: 4)]);
      final plan = planner.generate(
        subjects: [subject('phys')],
        topics: [topic('a', 'phys', 600)],
        availability: busy,
        today: today,
      );

      expect(plan.minutesOn(today), lessThanOrEqualTo(60));
    });
  });

  group('replanning mid-day', () {
    test('does not offer blocks that start in the past', () {
      const threePm = 15 * 60;
      final plan = planner.generate(
        subjects: [subject('phys')],
        topics: [topic('a', 'phys', 600)],
        availability: flat(300),
        today: today,
        todayStartMinute: threePm,
      );

      for (final s in plan.onDate(today)) {
        expect(s.startMinuteOfDay, greaterThanOrEqualTo(threePm));
      }
    });

    test('later days still start at the normal hour', () {
      final plan = planner.generate(
        subjects: [subject('phys')],
        topics: [topic('a', 'phys', 600)],
        availability: flat(120),
        today: today,
        todayStartMinute: 22 * 60,
      );

      final tomorrow = plan.onDate(today.add(const Duration(days: 1)));
      expect(tomorrow, isNotEmpty);
      expect(tomorrow.first.startMinuteOfDay, 6 * 60);
    });

    test('reduced capacity today pushes work to later days', () {
      final full = planner.generate(
        subjects: [subject('phys')],
        topics: [topic('a', 'phys', 600)],
        availability: flat(120),
        today: today,
      );

      // An hour of today has already been spent, expressed as capacity.
      final reduced = planner.generate(
        subjects: [subject('phys')],
        topics: [topic('a', 'phys', 600)],
        availability: flat(120).withOverride(today, 60),
        today: today,
      );

      expect(reduced.minutesOn(today), lessThan(full.minutesOn(today)));
      expect(reduced.minutesOn(today), lessThanOrEqualTo(60));
      expect(reduced.feasibility.unscheduledMinutes, 0);
    });
  });

  group('session ids', () {
    test('are stable across regeneration', () {
      List<String> idsFrom() => planner
          .generate(
            subjects: [subject('phys'), subject('math')],
            topics: [topic('a', 'phys', 400), topic('b', 'math', 400)],
            availability: flat(120),
            today: today,
          )
          .sessions
          .map((s) => s.id)
          .toList();

      expect(idsFrom(), idsFrom());
    });

    test('are unique within a plan', () {
      final plan = planner.generate(
        subjects: [subject('phys'), subject('math')],
        topics: [topic('a', 'phys', 900), topic('b', 'math', 900)],
        availability: flat(240),
        today: today,
      );

      final ids = plan.sessions.map((s) => s.id).toSet();
      expect(ids.length, plan.sessions.length);
    });
  });

  group('feasibility', () {
    test('reports the shortfall when there is more work than time', () {
      final exam = today.add(const Duration(days: 4)); // 5 days inclusive
      final plan = planner.generate(
        subjects: [subject('phys', exam: exam)],
        topics: [topic('a', 'phys', 800)],
        availability: flat(100),
        today: today,
      );

      expect(plan.feasibility.fits, isFalse);
      expect(plan.feasibility.unscheduledMinutes, 300);
      expect(plan.feasibility.warnings, isNotEmpty);
      expect(plan.feasibility.warnings.first, contains('phys'));
      expect(plan.feasibility.loadRatio, greaterThan(1.0));
    });

    test('is satisfied when the work fits', () {
      final plan = planner.generate(
        subjects: [subject('phys', exam: today.add(const Duration(days: 4)))],
        topics: [topic('a', 'phys', 400)],
        availability: flat(100),
        today: today,
      );

      expect(plan.feasibility.fits, isTrue);
      expect(plan.feasibility.unscheduledMinutes, 0);
    });

    test('counts only work that remains', () {
      final plan = planner.generate(
        subjects: [subject('phys')],
        topics: [topic('a', 'phys', 600, done: 400)],
        availability: flat(100),
        today: today,
      );

      expect(plan.feasibility.requiredMinutes, 200);
    });

    test('handles no subjects at all', () {
      final plan = planner.generate(
        subjects: const [],
        topics: const [],
        availability: flat(100),
        today: today,
      );

      expect(plan.sessions, isEmpty);
      expect(plan.feasibility.fits, isTrue);
    });
  });

  group('priorities', () {
    test('favours the nearer exam', () {
      final plan = planner.generate(
        subjects: [
          subject('phys', exam: today.add(const Duration(days: 5))),
          subject('math', exam: today.add(const Duration(days: 60))),
        ],
        topics: [topic('p1', 'phys', 400), topic('m1', 'math', 400)],
        availability: flat(120),
        today: today,
      );

      var physics = 0;
      var maths = 0;
      for (var i = 0; i < 5; i++) {
        for (final s in plan.onDate(today.add(Duration(days: i)))) {
          if (s.subjectId == 'phys') physics += s.durationMinutes;
          if (s.subjectId == 'math') maths += s.durationMinutes;
        }
      }
      expect(physics, greaterThan(maths));
    });

    test('weighs workload, not just deadline distance', () {
      // The case a deadline-only heuristic gets backwards:
      //   heavy — exam in 60 days, 40h of work  -> needs ~40 min/day
      //   light — exam in 30 days,  1h of work  -> needs  ~2 min/day
      // Scoring on 1/daysToExam would rank `light` twice as urgent.
      final plan = planner.generate(
        subjects: [
          subject('heavy', exam: today.add(const Duration(days: 60))),
          subject('light', exam: today.add(const Duration(days: 30))),
        ],
        topics: [topic('h', 'heavy', 2400), topic('l', 'light', 60)],
        availability: flat(120),
        today: today,
      );

      var heavy = 0;
      var light = 0;
      for (var i = 0; i < 7; i++) {
        for (final s in plan.onDate(today.add(Duration(days: i)))) {
          if (s.subjectId == 'heavy') heavy += s.durationMinutes;
          if (s.subjectId == 'light') light += s.durationMinutes;
        }
      }

      expect(heavy, greaterThan(light),
          reason: 'the heavier subject needs far more minutes per day');
      expect(plan.feasibility.fits, isTrue);
    });

    test('a subject in crisis may override interleaving', () {
      final plan = planner.generate(
        subjects: [
          subject('urgent', exam: today.add(const Duration(days: 2))),
          subject('distant', exam: today.add(const Duration(days: 120))),
        ],
        topics: [topic('u', 'urgent', 340), topic('d', 'distant', 2000)],
        availability: flat(180),
        today: today,
      );

      final first = plan.onDate(today);
      expect(first, isNotEmpty);
      expect(first.every((s) => s.subjectId == 'urgent'), isTrue,
          reason: 'an exam in two days should not yield a third of the day');
    });

    test('reviews cannot crowd out new material entirely', () {
      // Twelve finished topics all fall due for review at once.
      final done = [
        for (var i = 0; i < 12; i++)
          topic('d$i', 'phys', 60,
              done: 60,
              status: TopicStatus.done,
              completedOn: today.subtract(const Duration(days: 1))),
      ];

      final plan = planner.generate(
        subjects: [subject('phys')],
        topics: [...done, topic('new', 'phys', 600)],
        availability: flat(120),
        today: today,
      );

      final firstDay = plan.onDate(today);
      final reviewMinutes = firstDay
          .where((s) => s.isReview)
          .fold(0, (a, s) => a + s.durationMinutes);

      expect(reviewMinutes, lessThanOrEqualTo(48)); // 40% of 120
      expect(firstDay.any((s) => !s.isReview), isTrue,
          reason: 'new material must still get a look in');
    });

    test('never schedules a subject past its exam', () {
      final exam = today.add(const Duration(days: 3));
      final plan = planner.generate(
        subjects: [
          subject('phys', exam: exam),
          subject('math', exam: today.add(const Duration(days: 40))),
        ],
        topics: [topic('p1', 'phys', 2000), topic('m1', 'math', 400)],
        availability: flat(120),
        today: today,
      );

      for (final s in plan.sessions.where((s) => s.subjectId == 'phys')) {
        expect(s.date.isAfter(exam), isFalse,
            reason: 'physics scheduled after the exam');
      }
    });

    test('interleaves subjects rather than blocking them', () {
      final plan = planner.generate(
        subjects: [subject('phys'), subject('math')],
        topics: [topic('p1', 'phys', 2000), topic('m1', 'math', 2000)],
        availability: flat(300),
        today: today,
      );

      final first = plan.onDate(today).map((s) => s.subjectId).toList();
      expect(first.length, greaterThan(3));

      var run = 1;
      for (var i = 1; i < first.length; i++) {
        run = first[i] == first[i - 1] ? run + 1 : 1;
        expect(run, lessThanOrEqualTo(2),
            reason: 'more than two consecutive blocks of ${first[i]}');
      }
    });
  });

  group('an exam that has been', () {
    final gone = today.subtract(const Duration(days: 3));

    test('does not make the plan impossible', () {
      // The bug this fixes: a subject whose exam has passed still had work
      // outstanding, the day loop rightly refused to schedule it, and the
      // feasibility pass then reported the plan impossible — permanently, and
      // over a subject nothing can be done about. Today's banner said the
      // plan did not fit and there was no way to make it fit.
      final plan = planner.generate(
        subjects: [subject('bio', exam: gone)],
        topics: [topic('b1', 'bio', 600)],
        availability: flat(120),
        today: today,
      );

      expect(plan.feasibility.fits, isTrue);
      expect(plan.feasibility.unscheduledMinutes, 0);
      expect(plan.feasibility.warnings, isEmpty);
    });

    test('is left out of the work the plan is measured against', () {
      final plan = planner.generate(
        subjects: [subject('bio', exam: gone)],
        topics: [topic('b1', 'bio', 600)],
        availability: flat(120),
        today: today,
      );
      expect(plan.feasibility.requiredMinutes, 0,
          reason: 'work that can never be scheduled is not required work');
    });

    test('does not drag a live subject down with it', () {
      final plan = planner.generate(
        subjects: [
          subject('bio', exam: gone),
          subject('phys', exam: today.add(const Duration(days: 10))),
        ],
        topics: [topic('b1', 'bio', 600), topic('p1', 'phys', 300)],
        availability: flat(120),
        today: today,
      );

      expect(plan.feasibility.fits, isTrue);
      expect(plan.feasibility.requiredMinutes, 300);
      expect(plan.sessions.every((s) => s.subjectId == 'phys'), isTrue);
    });

    test('a live subject that genuinely does not fit still says so', () {
      // The guard against over-correcting: silencing a passed exam must not
      // silence the warning that matters.
      final plan = planner.generate(
        subjects: [
          subject('bio', exam: gone),
          subject('phys', exam: today.add(const Duration(days: 2))),
        ],
        topics: [topic('b1', 'bio', 600), topic('p1', 'phys', 2000)],
        availability: flat(60),
        today: today,
      );

      expect(plan.feasibility.fits, isFalse);
      expect(plan.feasibility.warnings.any((w) => w.contains('phys')), isTrue);
      expect(plan.feasibility.warnings.any((w) => w.contains('bio')), isFalse,
          reason: 'nothing can be done about bio, so nothing is said about it');
    });
  });

  group('exam time', () {
    test('nothing for that subject is scheduled after the exam starts', () {
      final plan = planner.generate(
        subjects: [subject('phys', exam: today, examMinute: 9 * 60)],
        topics: [topic('p1', 'phys', 600)],
        availability: flat(600),
        today: today,
      );

      final onExamDay = plan.onDate(today);
      expect(onExamDay, isNotEmpty, reason: 'the morning is still usable');
      for (final s in onExamDay) {
        expect(s.startMinuteOfDay + s.durationMinutes, lessThanOrEqualTo(9 * 60),
            reason: 'revising after the paper has started is not preparation');
      }
    });

    test('the rest of the exam day still goes to other subjects', () {
      // The reason a subject whose exam has passed is retired for the day
      // rather than ending the day outright.
      final plan = planner.generate(
        subjects: [
          subject('phys', exam: today, examMinute: 9 * 60),
          subject('math', exam: today.add(const Duration(days: 30))),
        ],
        topics: [topic('p1', 'phys', 600), topic('m1', 'math', 600)],
        availability: flat(600),
        today: today,
      );

      final afterTheExam = plan
          .onDate(today)
          .where((s) => s.startMinuteOfDay >= 9 * 60)
          .toList();
      expect(afterTheExam, isNotEmpty);
      expect(afterTheExam.every((s) => s.subjectId == 'math'), isTrue);
    });

    test('an exam before the day opens gets no blocks on its own day', () {
      final plan = planner.generate(
        subjects: [subject('phys', exam: today, examMinute: 6 * 60)],
        topics: [topic('p1', 'phys', 600)],
        availability: flat(600),
        today: today,
      );

      expect(plan.onDate(today), isEmpty);
    });

    test('without a time the whole exam day is still usable', () {
      // The pre-existing contract. Every subject entered before exam times
      // existed relies on it.
      final plan = planner.generate(
        subjects: [subject('phys', exam: today)],
        topics: [topic('p1', 'phys', 600)],
        availability: flat(600),
        today: today,
      );

      expect(
        plan.onDate(today).any((s) => s.startMinuteOfDay >= 12 * 60),
        isTrue,
        reason: 'a date-only exam must not lose the afternoon',
      );
    });

    test('a morning exam outranks an identical one later in the day', () {
      // Both subjects have the same work and the same exam date, so the only
      // thing separating them is how much of today they have left. Least
      // slack must win.
      final plan = planner.generate(
        subjects: [
          subject('early', exam: today, examMinute: 10 * 60),
          subject('late', exam: today, examMinute: 20 * 60),
        ],
        topics: [topic('e', 'early', 600), topic('l', 'late', 600)],
        availability: flat(120),
        today: today,
      );

      final first = plan.onDate(today).first;
      expect(first.subjectId, 'early');
    });

    test('a busy morning does not push work past the exam', () {
      // Class until 10:45, exam at 11:00. The 15 minutes between them cannot
      // hold a block, and the planner must leave them alone rather than
      // schedule across the exam — the case that made the cutoff a per-block
      // check rather than a per-day one.
      final plan = planner.generate(
        subjects: [subject('phys', exam: today, examMinute: 11 * 60)],
        topics: [topic('p1', 'phys', 600)],
        availability: Availability(
          minutesByWeekday: {for (var d = 1; d <= 7; d++) d: 600},
          busy: [
            BusySlot(
              id: 'class',
              label: 'class',
              startMinute: 6 * 60,
              endMinute: 10 * 60 + 45,
              weekday: today.weekday,
            ),
          ],
        ),
        today: today,
      );

      expect(plan.onDate(today), isEmpty);
    });
  });

  group('prerequisites', () {
    test('never starts a topic before its prerequisite finishes', () {
      final plan = planner.generate(
        subjects: [subject('phys')],
        topics: [
          topic('basics', 'phys', 200),
          topic('advanced', 'phys', 200, prereqs: ['basics']),
        ],
        availability: flat(100),
        today: today,
      );

      // Only the *study* blocks gate the prerequisite. Reviews of `basics`
      // carry the same topicId and land up to 21 days later, so including
      // them here would compare against the wrong date entirely.
      final lastBasics = plan.sessions
          .where((s) => s.topicId == 'basics' && !s.isReview)
          .map((s) => s.date)
          .reduce((a, b) => a.isAfter(b) ? a : b);

      for (final s in plan.sessions
          .where((s) => s.topicId == 'advanced' && !s.isReview)) {
        expect(s.date.isBefore(lastBasics), isFalse,
            reason: 'advanced started before basics was finished');
      }
    });

    test('a prerequisite cycle terminates and is reported', () {
      final plan = planner.generate(
        subjects: [subject('phys')],
        topics: [
          topic('a', 'phys', 200, prereqs: ['b']),
          topic('b', 'phys', 200, prereqs: ['a']),
        ],
        availability: flat(100),
        today: today,
      );

      expect(plan.sessions, isEmpty);
      expect(plan.feasibility.unscheduledMinutes, 400);
      expect(
        plan.feasibility.warnings.any((w) => w.contains('cycle')),
        isTrue,
      );
    });

    test('a prerequisite that does not exist does not deadlock', () {
      final plan = planner.generate(
        subjects: [subject('phys')],
        topics: [topic('a', 'phys', 200, prereqs: ['ghost'])],
        availability: flat(100),
        today: today,
      );

      expect(plan.sessions, isNotEmpty);
      expect(plan.feasibility.fits, isTrue);
    });
  });

  group('spaced repetition', () {
    test('queues a review the day after a topic is finished', () {
      final plan = planner.generate(
        subjects: [subject('phys')],
        topics: [topic('a', 'phys', 100)],
        availability: flat(100),
        today: today,
      );

      final reviews = plan.sessions.where((s) => s.isReview).toList();
      expect(reviews, isNotEmpty);
      expect(
        reviews.any((r) => r.date == today.add(const Duration(days: 1))),
        isTrue,
      );
    });

    test('does not pile overdue reviews onto day one', () {
      // Finished two months ago: every rung of the ladder is long past.
      final plan = planner.generate(
        subjects: [subject('phys')],
        topics: [
          topic('a', 'phys', 100,
              done: 100,
              status: TopicStatus.done,
              completedOn: today.subtract(const Duration(days: 60))),
        ],
        availability: flat(100),
        today: today,
      );

      expect(plan.sessions.where((s) => s.isReview), isEmpty);
    });
  });

  group('replanning', () {
    test('absorbs a missed day instead of stranding the work', () {
      const work = 400;
      final subjects = [subject('phys')];
      final availability = flat(100);

      final before = planner.generate(
        subjects: subjects,
        topics: [topic('a', 'phys', work)],
        availability: availability,
        today: today,
      );
      expect(before.feasibility.fits, isTrue);

      // The student studied nothing on day one. Replan from tomorrow with the
      // same untouched progress.
      final tomorrow = today.add(const Duration(days: 1));
      final after = planner.generate(
        subjects: subjects,
        topics: [topic('a', 'phys', work)],
        availability: availability,
        today: tomorrow,
      );

      final newMaterial = after.sessions
          .where((s) => !s.isReview)
          .fold(0, (a, s) => a + s.durationMinutes);

      expect(after.feasibility.fits, isTrue);
      expect(newMaterial, work);
      expect(after.sessions.every((s) => !s.date.isBefore(tomorrow)), isTrue);
    });

    test('schedules only what is left after logged progress', () {
      final plan = planner.generate(
        subjects: [subject('phys')],
        topics: [topic('a', 'phys', 400, done: 300)],
        availability: flat(100),
        today: today,
      );

      final newMaterial = plan.sessions
          .where((s) => !s.isReview)
          .fold(0, (a, s) => a + s.durationMinutes);

      expect(newMaterial, 100);
    });
  });

  group('session shape', () {
    test('honours block length and leaves no tiny stubs', () {
      final plan = planner.generate(
        subjects: [subject('phys')],
        topics: [topic('a', 'phys', 305)],
        availability: flat(120),
        today: today,
      );

      for (final s in plan.sessions.where((s) => !s.isReview)) {
        expect(s.durationMinutes, greaterThanOrEqualTo(5));
        expect(s.durationMinutes, lessThanOrEqualTo(50));
      }
    });

    test('blocks within a day do not overlap', () {
      final plan = planner.generate(
        subjects: [subject('phys'), subject('math')],
        topics: [topic('a', 'phys', 600), topic('b', 'math', 600)],
        availability: flat(240),
        today: today,
      );

      final day = plan.onDate(today);
      for (var i = 1; i < day.length; i++) {
        expect(day[i].startMinuteOfDay,
            greaterThanOrEqualTo(day[i - 1].endMinuteOfDay));
      }
    });
  });
}
