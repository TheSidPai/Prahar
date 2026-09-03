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

  /// Called after every plan rebuild. Cheap enough (four short strings + one
  /// broadcast) to run on each replan rather than trying to diff.
  static Future<void> updateNextBlock(List<StudySession> todaySessions,
      {DateTime? now}) async {
    if (!Platform.isAndroid) return;
    final at = now ?? DateTime.now();
    final upcoming = todaySessions
        .where((s) => s.endsAt.isAfter(at))
        .toList();

    if (upcoming.isEmpty) {
      await _push(null, null, null, 'none');
      return;
    }
    final next = upcoming.first;
    final ongoing = !next.startsAt.isAfter(at);
    await _push(
      next.topicTitle,
      next.subjectName,
      '${formatClock(next.startMinuteOfDay)} · '
          '${formatMinutes(next.durationMinutes)}',
      ongoing ? 'now' : 'next',
    );
  }

  static Future<void> _push(
      String? title, String? subject, String? time, String status) async {
    try {
      await _channel.invokeMethod('update', {
        'title': title,
        'subject': subject,
        'time': time,
        'status': status,
      });
    } catch (e) {
      // The widget is a nicety; a failed push must never break the app.
      debugPrint('Prahar: widget update failed: $e');
    }
  }
}
