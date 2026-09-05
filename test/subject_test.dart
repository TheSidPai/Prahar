import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/domain/models.dart';

/// The arithmetic behind "days left".
///
/// It is one method rather than three because the planner's urgency score, the
/// "needs X a day" figure on Progress and the same figure on a subject's own
/// page all divide by it. Three copies would disagree the first time one of
/// them was edited, and the student would be told two different things about
/// the same exam on two different screens.
void main() {
  final today = DateTime(2026, 9, 4);

  // The default study window: 06:00 to 22:00, so a 16-hour day.
  const windowStart = 6 * 60;
  const windowEnd = 22 * 60;

  Subject exam({DateTime? date, int? minute}) => Subject(
    id: 's',
    name: 'Physics',
    examDate: date,
    examMinuteOfDay: minute,
  );

  double? days(Subject s, {DateTime? from}) => s.prepDaysFrom(
    from ?? today,
    windowStartMinute: windowStart,
    windowEndMinute: windowEnd,
  );

  group('with no exam time', () {
    test('the exam day counts as a whole day, exactly as before', () {
      expect(days(exam(date: today)), 1.0);
      expect(days(exam(date: DateTime(2026, 9, 14))), 11.0);
    });

    test('no exam date means no answer, not zero', () {
      expect(days(exam()), isNull);
    });
  });

  group('with an exam time', () {
    test('an exam today is worth only the hours before it', () {
      // 06:00 to 09:00 of a 16-hour window.
      expect(days(exam(date: today, minute: 9 * 60)), closeTo(3 / 16, 0.001));
    });

    test('an exam tomorrow is a full day plus tomorrow morning', () {
      final tomorrow = DateTime(2026, 9, 5);
      expect(
        days(exam(date: tomorrow, minute: 9 * 60)),
        closeTo(1 + 3 / 16, 0.001),
      );
    });

    test('a first-thing exam leaves nothing on the day itself', () {
      expect(days(exam(date: today, minute: windowStart)), 0.0);
      expect(
        days(exam(date: today, minute: 5 * 60)),
        0.0,
        reason: 'an exam before the window opens cannot be prepared for',
      );
    });

    test('an exam after the window closes still gives only a whole day', () {
      expect(days(exam(date: today, minute: 23 * 60)), 1.0);
    });
  });

  test('a past exam is out of time, never negative', () {
    expect(days(exam(date: DateTime(2026, 9, 1))), 0.0);
    expect(days(exam(date: DateTime(2026, 9, 1), minute: 540)), 0.0);
  });

  test('the time of day of [from] is ignored — a day begun is still a day', () {
    // Otherwise "days left" would tick down through the afternoon and the
    // per-day figure would climb while the student was studying.
    final morning = DateTime(2026, 9, 4, 7);
    final evening = DateTime(2026, 9, 4, 21);
    final s = exam(date: DateTime(2026, 9, 10));
    expect(days(s, from: morning), days(s, from: evening));
  });

  group('the daily demand', () {
    // A 16-hour window, so a day cannot hold more than 960 minutes of study
    // however the arithmetic comes out.
    const windowMinutes = windowEnd - windowStart;

    ({int? perDay, bool impossible}) demand(
      Subject s, {
      required int remaining,
      DateTime? at,
    }) => s.examDemand(
      remainingMinutes: remaining,
      from: at ?? today,
      studyMinutesPerDay: windowMinutes,
      windowStartMinute: windowStart,
      windowEndMinute: windowEnd,
    );

    test('is a plain rate when the work fits', () {
      final d = demand(
        exam(date: DateTime(2026, 9, 14)),
        remaining: 660, // 11h over 11 days
      );
      expect(d.perDay, 60);
      expect(d.impossible, isFalse);
    });

    test('refuses to quote a rate no day could hold', () {
      // The bug this guard exists for: 4h of work against an exam at 9am
      // divides by 0.19 of a day and reports "needs 56h a day".
      final d = demand(exam(date: today, minute: 9 * 60), remaining: 240);
      expect(d.perDay, isNull, reason: '56h a day is an artefact, not advice');
      expect(d.impossible, isTrue);
    });

    test('a rate right at the edge of a day is still quoted', () {
      final d = demand(exam(date: today), remaining: windowMinutes);
      expect(d.perDay, windowMinutes);
      expect(d.impossible, isFalse);
    });

    test('one minute past a full day is not', () {
      final d = demand(exam(date: today), remaining: windowMinutes + 1);
      expect(d.perDay, isNull);
      expect(d.impossible, isTrue);
    });

    test('a passed exam is impossible, never a number', () {
      final d = demand(exam(date: DateTime(2026, 9, 1)), remaining: 60);
      expect(d.perDay, isNull);
      expect(d.impossible, isTrue);
    });

    test('finished work says nothing at all', () {
      final d = demand(exam(date: DateTime(2026, 9, 14)), remaining: 0);
      expect(d.perDay, isNull);
      expect(
        d.impossible,
        isFalse,
        reason: 'nothing left to do is not a failure to fit it in',
      );
    });

    test('no exam date says nothing at all', () {
      final d = demand(exam(), remaining: 600);
      expect(d.perDay, isNull);
      expect(d.impossible, isFalse);
    });
  });

  group('examHasPassed', () {
    test('is false on the day of the exam, however late', () {
      expect(
        exam(date: today).examHasPassed(DateTime(2026, 9, 4, 23)),
        isFalse,
      );
      expect(
        exam(
          date: today,
          minute: 9 * 60,
        ).examHasPassed(DateTime(2026, 9, 4, 23)),
        isFalse,
        reason: 'the paper is over, but "exam passed" is for another day',
      );
    });

    test('is true the day after', () {
      expect(exam(date: today).examHasPassed(DateTime(2026, 9, 5)), isTrue);
    });

    test('is false without a date', () {
      expect(exam().examHasPassed(today), isFalse);
    });
  });

  group('examAt', () {
    test('is the date when the time is unknown', () {
      expect(exam(date: today).examAt, today);
    });

    test('carries the time when it is known', () {
      expect(
        exam(date: today, minute: 14 * 60 + 45).examAt,
        DateTime(2026, 9, 4, 14, 45),
      );
    });
  });
}
