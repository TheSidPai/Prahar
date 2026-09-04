import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/domain/schedule.dart';
import 'package:prahar/domain/today_focus.dart';

/// The hero-selection rules for the editorial Today screen.
///
/// Pulled out of the widget on purpose: these are the cases that make a
/// "what now?" screen either trustworthy or subtly wrong, and none of them is
/// pleasant to reproduce by hand on a device at the right time of day.
void main() {
  StudySession block(int startMinute, int minutes, {String id = ''}) =>
      StudySession(
        id: id.isEmpty ? 'b$startMinute' : id,
        topicId: 't',
        subjectId: 's',
        topicTitle: 'Gene Replication',
        subjectName: 'Biology',
        date: DateTime(2026, 9, 5),
        startMinuteOfDay: startMinute,
        durationMinutes: minutes,
      );

  TodayFocus focus(
    List<StudySession> blocks,
    int nowMinute, {
    bool logged = false,
  }) =>
      focusFor(
        remaining: blocks,
        anythingLogged: logged,
        nowMinuteOfDay: nowMinute,
      );

  group('a block is running', () {
    test('leads with it and says how long is left', () {
      final f = focus([block(540, 40), block(660, 40)], 9 * 60 + 25);
      expect(f.kind, FocusKind.now);
      expect(f.session?.startMinuteOfDay, 540);
      expect(f.minutesLeft, 15);
    });

    test('the first minute counts as running', () {
      expect(focus([block(540, 40)], 540).kind, FocusKind.now);
    });

    test('the last minute counts as running', () {
      expect(focus([block(540, 40)], 579).kind, FocusKind.now);
    });

    test('the minute it ends does not', () {
      // Half-open interval, or a block would be both finished and current.
      expect(focus([block(540, 40)], 580).kind, FocusKind.next);
    });
  });

  group('between blocks', () {
    test('leads with the next one and counts down to it', () {
      final f = focus([block(540, 40), block(660, 40)], 10 * 60);
      expect(f.kind, FocusKind.next);
      expect(f.session?.startMinuteOfDay, 660);
      expect(f.minutesUntilStart, 60);
    });

    test('picks the earliest upcoming block, not the first in the list', () {
      final f = focus([block(1200, 40), block(660, 40)], 10 * 60);
      expect(f.session?.startMinuteOfDay, 660);
    });

    test('before the day starts, the first block is next', () {
      final f = focus([block(540, 40)], 6 * 60);
      expect(f.kind, FocusKind.next);
      expect(f.minutesUntilStart, 180);
    });
  });

  test('a block whose start has passed is due now, not overdue by hours', () {
    // The app left open through an untouched block. Its start time is behind
    // us, so counting down to it would print a negative number; it is simply
    // the thing to do.
    final f = focus([block(540, 40)], 23 * 60);
    expect(f.kind, FocusKind.next);
    expect(f.session?.startMinuteOfDay, 540);
    expect(f.minutesUntilStart, 0);
  });

  group('an empty day', () {
    test('with work behind it is finished', () {
      final f = focus([], 20 * 60, logged: true);
      expect(f.kind, FocusKind.allDone);
      expect(f.hasBlock, isFalse);
    });

    test('with nothing behind it was always empty', () {
      final f = focus([], 20 * 60);
      expect(f.kind, FocusKind.nothingPlanned);
      expect(f.hasBlock, isFalse);
    });

    test('tells the two apart — they deserve different words', () {
      expect(focus([], 20 * 60, logged: true).kind,
          isNot(focus([], 20 * 60).kind));
    });
  });
}
