import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;

import '../domain/format.dart';
import '../domain/schedule.dart';

/// Pushes what today's next block is to the home-screen widget process.
///
/// The widget cannot call into Dart — it is a passive `AppWidgetProvider` that
/// only wakes on broadcast — so anything it needs to render must be persisted
/// to shared storage first. This class does that, then asks Android to
/// re-render every instance of the widget.
class WidgetBridge {
  static const _channel = MethodChannel('prahar/widget');

  /// Called after every plan rebuild. Sends both the "next block" fields
  /// and the "today" extras (block 2 + progress) in one payload — the two
  /// widget flavours share the same store and pick the fields they need.
  static Future<void> updateNextBlock(
    List<StudySession> todaySessions, {
    DateTime? now,
    int doneMinutes = 0,
    int plannedMinutes = 0,
  }) async {
    if (!Platform.isAndroid) return;
    final at = now ?? DateTime.now();
    final upcoming = todaySessions.where((s) => s.endsAt.isAfter(at)).toList();

    final progress = plannedMinutes <= 0
        ? 0
        : ((doneMinutes / plannedMinutes) * 100).clamp(0, 100).round();
    final progressText = plannedMinutes <= 0
        ? 'No plan today'
        : '${formatMinutes(doneMinutes)} of ${formatMinutes(plannedMinutes)}';

    if (upcoming.isEmpty) {
      await _push({
        'title': '',
        'subject': '',
        'time': '',
        'title2': '',
        'subject2': '',
        'time2': '',
        'status': 'none',
        'progress': progress,
        'progressText': progressText,
      });
      return;
    }
    final first = upcoming[0];
    final second = upcoming.length > 1 ? upcoming[1] : null;
    final ongoing = !first.startsAt.isAfter(at);

    String fmt(StudySession s) =>
        '${formatClock(s.startMinuteOfDay)} · ${formatMinutes(s.durationMinutes)}';

    await _push({
      'title': first.topicTitle,
      'subject': first.subjectName,
      'time': fmt(first),
      'title2': second?.topicTitle ?? '',
      'subject2': second?.subjectName ?? '',
      'time2': second == null ? '' : fmt(second),
      'status': ongoing ? 'now' : 'next',
      'progress': progress,
      'progressText': progressText,
    });
  }

  static Future<void> _push(Map<String, Object?> payload) async {
    try {
      await _channel.invokeMethod('update', payload);
    } catch (e) {
      // The widget is a nicety; a failed push must never break the app.
      debugPrint('Prahar: widget update failed: $e');
    }
  }
}
