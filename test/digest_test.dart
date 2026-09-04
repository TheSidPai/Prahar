import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/domain/schedule.dart';

/// The evening digest's one line.
///
/// It lives in the domain beside `Feasibility.warnings` for the same reason:
/// the sentence is a property of the plan, not of a screen. These tests are
/// what stop the notification and the app disagreeing about what tomorrow is.
void main() {
  final tomorrow = DateTime(2026, 9, 5);

  StudySession block(
    String subject,
    String topic,
    int startMinute,
    int minutes, {
    DateTime? on,
  }) =>
      StudySession(
        id: '$subject|$startMinute',
        topicId: topic,
        subjectId: subject,
        topicTitle: topic,
        subjectName: subject,
        date: on ?? tomorrow,
        startMinuteOfDay: startMinute,
        durationMinutes: minutes,
      );

  Plan planOf(List<StudySession> sessions) => Plan(
        sessions: sessions,
        feasibility: const Feasibility(
          requiredMinutes: 0,
          availableMinutes: 0,
          unscheduledMinutes: 0,
          warnings: [],
        ),
        generatedAt: DateTime(2026, 9, 4),
      );

  test('counts the blocks, the time and the first start', () {
    final line = planOf([
      block('Biology', 'Genetics', 9 * 60, 40),
      block('Physics', 'Optics', 11 * 60, 50),
    ]).digestFor(tomorrow);

    expect(line, contains('2 blocks'));
    expect(line, contains('1h 30m'));
    expect(line, contains('from 09:00'));
    expect(line, contains('Biology, Physics'));
  });

  test('says one block in the singular', () {
    final line = planOf([block('Biology', 'Genetics', 9 * 60, 40)])
        .digestFor(tomorrow);
    expect(line, contains('1 block ·'));
  });

  test('names a subject once however many blocks it has', () {
    final line = planOf([
      block('Biology', 'Genetics', 9 * 60, 40),
      block('Biology', 'Ecology', 11 * 60, 40),
    ]).digestFor(tomorrow);

    expect('Biology'.allMatches(line).length, 1);
  });

  test('counts the tail once there are too many subjects to name', () {
    final line = planOf([
      block('Biology', 'a', 8 * 60, 30),
      block('Physics', 'b', 9 * 60, 30),
      block('Maths', 'c', 10 * 60, 30),
      block('Music', 'd', 11 * 60, 30),
    ]).digestFor(tomorrow);

    expect(line, contains('Biology, Physics and 2 more'));
  });

  test('names three subjects in full — the limit', () {
    final line = planOf([
      block('Biology', 'a', 8 * 60, 30),
      block('Physics', 'b', 9 * 60, 30),
      block('Maths', 'c', 10 * 60, 30),
    ]).digestFor(tomorrow);

    expect(line, contains('Biology, Physics, Maths'));
  });

  test('an empty day says so rather than saying nothing', () {
    // A digest that arrives blank looks like a bug. A clear day is news.
    expect(planOf([]).digestFor(tomorrow), 'Nothing scheduled. A clear day.');
  });

  test('describes the day asked for, not the plan as a whole', () {
    final line = planOf([
      block('Biology', 'today', 9 * 60, 40, on: DateTime(2026, 9, 4)),
      block('Physics', 'tomorrow', 14 * 60, 50),
    ]).digestFor(tomorrow);

    expect(line, contains('Physics'));
    expect(line, isNot(contains('Biology')));
    expect(line, contains('from 14:00'));
  });
}
