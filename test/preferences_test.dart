import 'package:flutter_test/flutter_test.dart';
import 'package:prahar/domain/preferences.dart';

/// The study window is user-editable, so every degenerate combination a person
/// can produce with two time pickers must land somewhere sane rather than
/// silently scheduling nothing.
void main() {
  group('validity', () {
    test('the default window is usable', () {
      expect(const Prefs().isUsable, isTrue);
    });

    test('a window narrower than one block is rejected', () {
      const p = Prefs(
        dayStartMinute: 9 * 60,
        dayEndMinute: 9 * 60 + 30,
        blockMinutes: 50,
      );
      expect(p.isUsable, isFalse);
    });

    test('a window exactly one block wide is allowed', () {
      const p = Prefs(
        dayStartMinute: 9 * 60,
        dayEndMinute: 10 * 60,
        blockMinutes: 60,
      );
      expect(p.isUsable, isTrue);
    });
  });

  group('parsing is defensive', () {
    test('missing keys fall back to the defaults', () {
      final p = Prefs.fromMap({});
      expect(p.dayStartMinute, 6 * 60);
      expect(p.dayEndMinute, 22 * 60);
      expect(p.blockMinutes, 50);
    });

    test('unparseable values fall back rather than throwing', () {
      final p = Prefs.fromMap({'day_start': 'banana', 'block_minutes': ''});
      expect(p.dayStartMinute, 6 * 60);
      expect(p.blockMinutes, 50);
    });

    test('an inverted window is replaced, not stored', () {
      final p = Prefs.fromMap({
        'day_start': '${22 * 60}',
        'day_end': '${6 * 60}',
      });
      expect(p.dayStartMinute, lessThan(p.dayEndMinute));
      expect(p.isUsable, isTrue);
    });

    test('absurd values are clamped into range', () {
      final p = Prefs.fromMap({
        'day_start': '-500',
        'day_end': '99999',
        'block_minutes': '100000',
        'break_minutes': '-5',
      });
      expect(p.dayStartMinute, greaterThanOrEqualTo(0));
      expect(p.dayEndMinute, lessThanOrEqualTo(24 * 60));
      expect(p.blockMinutes, lessThanOrEqualTo(180));
      expect(p.breakMinutes, greaterThanOrEqualTo(0));
    });

    test('a round trip through the map preserves everything', () {
      const p = Prefs(
        dayStartMinute: 17 * 60 + 30,
        dayEndMinute: 23 * 60,
        blockMinutes: 25,
        breakMinutes: 5,
      );
      final back = Prefs.fromMap(p.toMap());
      expect(back.dayStartMinute, p.dayStartMinute);
      expect(back.dayEndMinute, p.dayEndMinute);
      expect(back.blockMinutes, p.blockMinutes);
      expect(back.breakMinutes, p.breakMinutes);
    });
  });

  group('the planner config it produces', () {
    test('carries the window through', () {
      const p = Prefs(dayStartMinute: 18 * 60, dayEndMinute: 23 * 60);
      final c = p.toConfig();
      expect(c.dayStartMinute, 18 * 60);
      expect(c.dayEndMinute, 23 * 60);
    });

    test('a short block never gets a longer minimum', () {
      // A 15-minute block with the fixed 20-minute floor would reject every
      // block the planner tried to place.
      final c = const Prefs(blockMinutes: 15).toConfig();
      expect(c.minSessionMinutes, lessThanOrEqualTo(c.maxSessionMinutes));
    });
  });
}
