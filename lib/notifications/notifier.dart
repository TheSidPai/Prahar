import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../domain/format.dart';
import '../domain/schedule.dart';

/// On-device scheduled notifications. No push service, no server, no cost.
///
/// The whole plan is known ahead of time, so every reminder can be handed to
/// the OS as a local alarm. That makes reminders work offline, in aeroplane
/// mode, and with the app force-stopped — which push notifications do not.
class Notifier {
  final _plugin = FlutterLocalNotificationsPlugin();

  /// Bumped from `prahar_sessions` when the audio moved to alarm usage.
  ///
  /// A channel's importance, sound and audio attributes are frozen at creation.
  /// Editing them in code does nothing for anyone who already ran the app — the
  /// only way to change them is a new channel id. Bump the suffix again if
  /// these settings ever change, or the change will appear to work in
  /// development and silently do nothing for existing installs.
  static const _channelId = 'prahar_sessions_v2';
  static const _channelName = 'Study sessions';
  static const _digestChannelId = 'prahar_digest';

  /// Study blocks are announced at alarm volume rather than notification
  /// volume. The channel was already IMPORTANCE_HIGH and audibly configured,
  /// yet reminders still went unheard: notification volume is a separate,
  /// often near-silent slider, especially on Xiaomi. Alarm usage borrows the
  /// alarm stream instead, which people keep loud.
  ///
  /// It does NOT set bypassDnd, so Do Not Disturb and Focus modes still
  /// silence it — deliberately, so the app cannot talk over a deliberate
  /// silence.
  static const _sessionDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Reminders for scheduled study blocks',
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      playSound: true,
      enableVibration: true,
      enableLights: true,
    ),
  );

  /// How far ahead to hand alarms to the OS.
  ///
  /// iOS refuses more than 64 pending notifications and Android's exact-alarm
  /// budget is finite too, so we keep a rolling window and top it up whenever
  /// the plan changes or the app is opened, rather than dumping a whole
  /// semester on the OS at once.
  static const windowDays = 14;
  static const maxPending = 56;

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    _initTimeZone();

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  /// Resolves the device's IANA zone without pulling in another plugin.
  ///
  /// `timezone` needs a named location, but Dart only exposes an abbreviation
  /// and an offset. Matching on the current offset is exact for zones without
  /// DST (India included) and, for the rest, picks a zone that agrees with the
  /// device for the two weeks we actually schedule.
  void _initTimeZone() {
    tzdata.initializeTimeZones();
    final now = DateTime.now();

    try {
      tz.setLocalLocation(tz.getLocation(now.timeZoneName));
      return;
    } catch (_) {
      // Abbreviation like "IST" is not a location name — fall through.
    }

    final offsetMs = now.timeZoneOffset.inMilliseconds;
    for (final loc in tz.timeZoneDatabase.locations.values) {
      if (loc.currentTimeZone.offset == offsetMs) {
        tz.setLocalLocation(loc);
        return;
      }
    }
    tz.setLocalLocation(tz.UTC);
  }

  // --------------------------------------------------------- permissions

  /// Android 13+ requires the user to grant notifications explicitly.
  Future<bool> requestPermissions() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;

    final granted = await android.requestNotificationsPermission() ?? false;

    // Android 12+ gates minute-accurate alarms behind a separate, easily
    // missed setting. Without it the OS batches reminders into its own idle
    // windows and a 6pm reminder can land at 7:20pm.
    await android.requestExactAlarmsPermission();

    return granted;
  }

  Future<bool> canScheduleExact() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    return await android.canScheduleExactNotifications() ?? true;
  }

  // ---------------------------------------------------------- scheduling

  /// Replaces every pending session alarm with the current plan.
  ///
  /// Cancel-then-reschedule rather than diffing: the window is at most a few
  /// dozen alarms, and a stale reminder for a session that no longer exists is
  /// far more damaging to trust than a few milliseconds of extra work.
  ///
  /// Only ids at or above [_sessionIdBase] are cancelled. `cancelAll()` would
  /// also destroy the daily digest and any test reminder, which are not part of
  /// the plan — and since a replan happens on every edit, the digest would
  /// silently never survive to fire.
  Future<void> syncFromPlan(Plan plan, {DateTime? now}) async {
    await init();
    final from = now ?? DateTime.now();

    for (final p in await _plugin.pendingNotificationRequests()) {
      if (p.id >= _sessionIdBase) await _plugin.cancel(p.id);
    }

    final horizon = from.add(const Duration(days: windowDays));
    final upcoming = plan.sessions
        .where((s) => s.status == SessionStatus.planned)
        .where((s) => s.startsAt.isAfter(from) && s.startsAt.isBefore(horizon))
        .toList()
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));

    for (final session in upcoming.take(maxPending)) {
      await _scheduleSession(session);
    }
  }

  Future<void> _scheduleSession(StudySession s) async {
    final title = s.isReview
        ? 'Review: ${s.topicTitle}'
        : '${s.subjectName} · ${formatMinutes(s.durationMinutes)}';
    final body = s.isReview
        ? 'Quick recall pass — ${formatMinutes(s.durationMinutes)}'
        : s.topicTitle;

    try {
      await _plugin.zonedSchedule(
        _idFor(s),
        title,
        body,
        tz.TZDateTime.from(s.startsAt, tz.local),
        _sessionDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: s.topicId,
      );
    } catch (e) {
      // A denied exact-alarm permission throws rather than degrading. Losing
      // one reminder must not take the app down with it.
      debugPrint('Prahar: could not schedule ${s.id}: $e');
    }
  }

  /// Evening summary of tomorrow's plan. Repeats daily at [hour]:[minute].
  Future<void> scheduleDailyDigest({
    required int hour,
    required int minute,
    required String body,
  }) async {
    await init();
    var when = tz.TZDateTime.local(
      tz.TZDateTime.now(tz.local).year,
      tz.TZDateTime.now(tz.local).month,
      tz.TZDateTime.now(tz.local).day,
      hour,
      minute,
    );
    if (when.isBefore(tz.TZDateTime.now(tz.local))) {
      when = when.add(const Duration(days: 1));
    }

    try {
      await _plugin.zonedSchedule(
        _digestId,
        "Tomorrow's plan",
        body,
        when,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _digestChannelId,
            'Daily digest',
            channelDescription: 'An evening look at tomorrow',
            importance: Importance.defaultImportance,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      debugPrint('Prahar: could not schedule digest: $e');
    }
  }

  Future<void> cancelAll() => _plugin.cancelAll();

  Future<int> pendingCount() async =>
      (await _plugin.pendingNotificationRequests()).length;

  /// Fires a one-off reminder shortly from now.
  ///
  /// The only way to check the whole delivery path — alarm registered, process
  /// woken, notification actually drawn — without waiting for a real study
  /// block. Worth re-running after changing any battery or autostart setting,
  /// which on some vendors silently breaks delivery while leaving the alarm
  /// registered.
  Future<DateTime> scheduleTest({
    Duration delay = const Duration(minutes: 1),
  }) async {
    await init();
    final when = DateTime.now().add(delay);

    await _plugin.zonedSchedule(
      _testId,
      'Test reminder',
      'Delivery works. Scheduled '
          '${delay.inSeconds}s earlier, at ${formatClock(when.hour * 60 + when.minute)}.',
      tz.TZDateTime.from(when, tz.local),
      _sessionDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
    return when;
  }

  // Reserved ids. Session alarms start at [_sessionIdBase] so they can be
  // cancelled as a group without touching these.
  static const _digestId = 1;
  static const _testId = 2;
  static const _sessionIdBase = 1000;

  /// Deterministic 32-bit id from the session's slot, so rescheduling the same
  /// block twice cannot produce a duplicate alarm.
  int _idFor(StudySession s) {
    final days = s.date.difference(DateTime(2020)).inDays;
    return _sessionIdBase + (days * 1440 + s.startMinuteOfDay) % 2000000000;
  }
}
