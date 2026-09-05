import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
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

  /// Implemented in `MainActivity.kt`. Two methods of hand-written platform
  /// code, in preference to a package that would drag in an Android SDK 37
  /// requirement for a single API call.
  static const _batteryChannel = MethodChannel('prahar/battery');

  /// A channel's importance, sound and audio attributes are frozen at creation.
  /// Editing them in code does nothing for anyone who already ran the app — the
  /// only way to change them is a new channel id. Bump the suffix whenever any
  /// of those change, and retire the old id below, or the change will appear to
  /// work in development and silently do nothing on existing installs.
  static const _channelId = 'prahar_sessions_v3';
  static const _channelName = 'Study sessions';
  static const _digestChannelId = 'prahar_digest';

  /// Superseded ids, deleted on startup so the user's notification settings do
  /// not accumulate a dead channel per revision.
  static const _retiredChannelIds = ['prahar_sessions', 'prahar_sessions_v2'];

  /// The device's alarm tone, named explicitly.
  ///
  /// Channels otherwise inherit the *default notification sound*, and on this
  /// phone `settings get system notification_sound` is `null` — unset. The
  /// result was a reminder that vibrated and reached the lock screen in
  /// perfect silence, because there was no sound to play. Pointing at
  /// `alarm_alert` both fixes that and matches the alarm-stream routing below.
  /// It resolves at play time, so the user's own alarm tone is respected.
  static const _alarmSound = UriAndroidNotificationSound(
    'content://settings/system/alarm_alert',
  );

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
      sound: _alarmSound,
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

    // Channels are immutable, so each audio change needs a new id. Remove the
    // superseded ones so the user's notification settings list does not fill
    // up with identically-named dead channels.
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    for (final old in _retiredChannelIds) {
      try {
        await android?.deleteNotificationChannel(old);
      } catch (_) {
        // Deleting a channel that was never created is not an error worth
        // failing startup over.
      }
    }

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
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return true;

    final granted = await android.requestNotificationsPermission() ?? false;

    // Android 12+ gates minute-accurate alarms behind a separate, easily
    // missed setting. Without it the OS batches reminders into its own idle
    // windows and a 6pm reminder can land at 7:20pm.
    await android.requestExactAlarmsPermission();

    return granted;
  }

  /// Whether the app is exempt from battery optimisation.
  ///
  /// This is the difference between reminders working and not. Without the
  /// exemption Android freezes the process, and a correctly registered exact
  /// alarm cannot wake anything to post its notification — it silently arrives
  /// only when the user next opens the app by hand, which is precisely when a
  /// reminder is useless. Verified on a Xiaomi device: granting the exemption
  /// turned a reminder that never appeared into one that arrived on time.
  Future<bool> isBatteryExempt() async {
    if (!Platform.isAndroid) return true;
    try {
      final v = await _batteryChannel.invokeMethod<bool>(
        'isIgnoringBatteryOptimizations',
      );
      return v ?? true;
    } catch (e) {
      // Never nag on the strength of a failed check.
      debugPrint('Prahar: battery exemption check failed: $e');
      return true;
    }
  }

  /// Opens the system dialog offering to stop optimising this app.
  ///
  /// The dialog is a separate activity, so its answer is not available here.
  /// [AppState] re-checks on resume — `HomeScreen.didChangeAppLifecycleState`
  /// already refreshes alarms when the app comes back to the foreground.
  Future<bool> requestBatteryExemption() async {
    if (!Platform.isAndroid) return true;
    try {
      final opened = await _batteryChannel.invokeMethod<bool>(
        'requestIgnoreBatteryOptimizations',
      );
      return opened ?? false;
    } catch (e) {
      debugPrint('Prahar: battery exemption request failed: $e');
      return false;
    }
  }

  Future<bool> canScheduleExact() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
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
    final upcoming =
        plan.sessions
            .where((s) => s.status == SessionStatus.planned)
            .where(
              (s) => s.startsAt.isAfter(from) && s.startsAt.isBefore(horizon),
            )
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

  /// Replaces the pending evening digests with [entries].
  ///
  /// One notification per evening, each carrying its own summary, rather than
  /// a single daily-repeating alarm. `matchDateTimeComponents` would repeat
  /// the *same body* forever, so the first night it fired would be right and
  /// every night after it would confidently describe a day that had already
  /// happened. A rolling window costs a handful of pending alarms and is
  /// always true; if the app is not opened for a week the digests simply run
  /// out, which is the right failure — silence beats a wrong summary.
  ///
  /// Ids live in their own range so [syncFromPlan] (≥ [_sessionIdBase]) never
  /// touches them and vice versa.
  Future<void> syncDigests(List<({DateTime when, String body})> entries) async {
    await init();

    for (final p in await _plugin.pendingNotificationRequests()) {
      if (p.id == _digestId ||
          (p.id >= _digestIdBase && p.id < _digestIdBase + digestDays)) {
        await _plugin.cancel(p.id);
      }
    }

    final now = DateTime.now();
    var slot = 0;
    for (final e in entries.take(digestDays)) {
      if (!e.when.isAfter(now)) continue;
      try {
        await _plugin.zonedSchedule(
          _digestIdBase + slot,
          "Tomorrow's plan",
          e.body,
          tz.TZDateTime.from(e.when, tz.local),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              _digestChannelId,
              'Daily digest',
              channelDescription: 'An evening look at tomorrow',
              importance: Importance.defaultImportance,
            ),
          ),
          // Inexact on purpose: a summary is not time-critical, and inexact
          // alarms are not rationed the way exact ones are.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        slot++;
      } catch (e) {
        debugPrint('Prahar: could not schedule digest: $e');
      }
    }
  }

  /// Fires when a timer's work or break interval ends.
  ///
  /// The timer screen cannot be trusted to be visible — the phone will be face
  /// down, which is rather the point of a focus timer — so the end of each
  /// interval is handed to the OS as an alarm like everything else. Replaced
  /// on every phase change and cancelled when the timer stops.
  Future<void> scheduleTimerAlert({
    required DateTime when,
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin.cancel(_timerId);
    if (!when.isAfter(DateTime.now())) return;
    try {
      await _plugin.zonedSchedule(
        _timerId,
        title,
        body,
        tz.TZDateTime.from(when, tz.local),
        _sessionDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } catch (e) {
      debugPrint('Prahar: could not schedule timer alert: $e');
    }
  }

  Future<void> cancelTimerAlert() async {
    await init();
    await _plugin.cancel(_timerId);
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

  // Reserved ids, partitioned so each kind can be cancelled as a group without
  // destroying the others. An early version used cancelAll() in syncFromPlan,
  // which — since a replan happens on every edit — quietly deleted the digest
  // and any pending test reminder every time the student touched anything.
  //
  //     1        the original single repeating digest (retired; still
  //              cancelled by syncDigests so old installs shed it)
  //     2        test reminder
  //     3        study-timer interval alert
  //     100..106 the rolling evening digests
  //     1000+    study block alarms
  static const _digestId = 1;
  static const _testId = 2;
  static const _timerId = 3;
  static const _digestIdBase = 100;

  /// How many evenings of digest to keep pending. A week: long enough that a
  /// few days without opening the app costs nothing, short enough that the
  /// summaries are still true when they fire.
  static const digestDays = 7;

  static const _sessionIdBase = 1000;

  /// Deterministic 32-bit id from the session's slot, so rescheduling the same
  /// block twice cannot produce a duplicate alarm.
  int _idFor(StudySession s) {
    final days = s.date.difference(DateTime(2020)).inDays;
    return _sessionIdBase + (days * 1440 + s.startMinuteOfDay) % 2000000000;
  }
}
