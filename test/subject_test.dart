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
      expect(days(exam(date: tomorrow, minute: 9 * 60)),
          closeTo(1 + 3 / 16, 0.001));
    });

    test('a first-thing exam leaves nothing on the day itself', () {
      expect(days(exam(date: today, minute: windowStart)), 0.0);
      expect(days(exam(date: today, minute: 5 * 60)), 0.0,
          reason: 'an exam before the window opens cannot be prepared for');
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

  group('examAt', () {
    test('is the date when the time is unknown', () {
      expect(exam(date: today).examAt, today);
    });

    test('carries the time when it is known', () {
      expect(exam(date: today, minute: 14 * 60 + 45).examAt,
          DateTime(2026, 9, 4, 14, 45));
    });
  });
}
