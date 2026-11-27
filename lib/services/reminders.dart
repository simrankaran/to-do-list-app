import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../data/models.dart';

/// One notification to show at a point in time.
typedef PlannedAlert = ({
  int id,
  DateTime at,
  String title,
  String body,
  AlertStyle style,
  AlertSound sound,
});

/// Works out every future notification for [tasks]: an optional early
/// heads-up, the start alert and the end alert, soonest first.
List<PlannedAlert> planAlerts(List<Task> tasks, DateTime now) {
  final fmt = DateFormat.jm();
  final alerts = <PlannedAlert>[];
  for (final t in tasks) {
    if (t.done || !t.remind || !t.hasTimeSlot) continue;
    final start = t.startsAt!, end = t.endsAt!;
    final slot = '${fmt.format(start)} – ${fmt.format(end)}';
    // Three ids per task; the mask keeps them inside a 32-bit int.
    final base = (t.id.hashCode & 0x1fffffff) * 4;

    void add(int offset, DateTime at, String title, String body) {
      if (!at.isAfter(now)) return;
      alerts.add((
        id: base + offset,
        at: at,
        title: title,
        body: body,
        style: t.alertStyle,
        sound: t.alertSound,
      ));
    }

    if (t.earlyMinutes > 0) {
      add(
        2,
        start.subtract(Duration(minutes: t.earlyMinutes)),
        '⏰ In ${t.earlyMinutes} min: ${t.title}',
        'Starts at ${fmt.format(start)}',
      );
    }
    final startMsg = t.startMessage.trim(), endMsg = t.endMessage.trim();
    if (startMsg.isEmpty) {
      add(0, start, '▶ Time to start: ${t.title}', 'Scheduled $slot');
    } else {
      add(0, start, startMsg, '${t.title} · $slot');
    }
    if (endMsg.isEmpty) {
      add(
        1,
        end,
        "⏹ Time's up: ${t.title}",
        'Your $slot slot has ended. Mark it done?',
      );
    } else {
      add(1, end, endMsg, '${t.title} · ended ${fmt.format(end)}');
    }
  }
  alerts.sort((a, b) => a.at.compareTo(b.at));
  return alerts;
}

/// Schedules phone notifications for when a task's time slot starts and ends.
abstract interface class ReminderScheduler {
  /// Asks the user for permission to notify (and to use exact alarms).
  /// Returns false if notifications are off.
  Future<bool> requestPermission();

  /// Replaces every scheduled reminder with ones for [tasks].
  Future<void> sync(List<Task> tasks);

  /// Shows a sample notification right now so the user can hear and feel
  /// the chosen [style] and [sound]. Returns false if it couldn't be shown.
  Future<bool> preview(AlertStyle style, AlertSound sound);
}

/// Used on platforms without local notifications (web, desktop) and in tests.
class NoReminders implements ReminderScheduler {
  const NoReminders();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> sync(List<Task> tasks) async {}

  @override
  Future<bool> preview(AlertStyle style, AlertSound sound) async => false;
}

/// Local notifications via `flutter_local_notifications` (Android and iOS).
class LocalReminders implements ReminderScheduler {
  LocalReminders._();

  static final _plugin = fln.FlutterLocalNotificationsPlugin();

  /// iOS keeps at most 64 pending notifications; stay under it everywhere.
  static const _maxPending = 60;

  static const _previewId = 0x7ffffff0;

  Future<void> _queue = Future.value();
  static bool _askedExact = false;

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Sets up notifications, or returns [NoReminders] where unsupported.
  static Future<ReminderScheduler> create() async {
    if (!supported) return const NoReminders();
    try {
      tz_data.initializeTimeZones();
      await _plugin.initialize(
        settings: const fln.InitializationSettings(
          android: fln.AndroidInitializationSettings('@mipmap/launcher_icon'),
          iOS: fln.DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      return LocalReminders._();
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
      return const NoReminders();
    }
  }

  /// On Android the sound and vibration belong to the notification channel
  /// and can't change after it is created, so each style/sound pair gets its
  /// own channel.
  static fln.NotificationDetails _details(AlertStyle style, AlertSound sound) {
    final loud = style == AlertStyle.sound;
    final quiet = style == AlertStyle.silent;
    final custom = loud && sound != AlertSound.standard;
    return fln.NotificationDetails(
      android: fln.AndroidNotificationDetails(
        loud ? 'tasks_sound_${sound.key}' : 'tasks_${style.name}',
        loud ? 'Task alerts · ${sound.label}' : 'Task alerts · ${style.label}',
        channelDescription: "Alerts when a task's time slot starts and ends",
        importance: quiet ? fln.Importance.low : fln.Importance.high,
        priority: quiet ? fln.Priority.low : fln.Priority.high,
        category: fln.AndroidNotificationCategory.reminder,
        playSound: loud,
        sound: custom
            ? fln.RawResourceAndroidNotificationSound(sound.key)
            : null,
        enableVibration: !quiet,
      ),
      iOS: fln.DarwinNotificationDetails(
        presentAlert: true,
        presentSound: loud,
      ),
    );
  }

  fln.AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        fln.AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> requestPermission() async {
    try {
      final android = _android;
      if (android != null) {
        final granted = await android.requestNotificationsPermission() ?? true;
        // Exact alarms are granted on a system settings page; send the user
        // there at most once per session. Without it, alerts may be a few
        // minutes late instead of exact.
        if (!_askedExact &&
            (await android.canScheduleExactNotifications()) != true) {
          _askedExact = true;
          await android.requestExactAlarmsPermission();
        }
        return granted;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            fln.IOSFlutterLocalNotificationsPlugin
          >();
      return await ios?.requestPermissions(alert: true, sound: true) ?? false;
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
      return false;
    }
  }

  @override
  Future<bool> preview(AlertStyle style, AlertSound sound) async {
    try {
      final android = _android;
      if (android != null &&
          (await android.requestNotificationsPermission()) == false) {
        return false;
      }
      await _plugin.show(
        id: _previewId,
        title: 'This is how your alert will arrive',
        body: style == AlertStyle.sound
            ? 'Sound: ${sound.label}'
            : '${style.label}: ${style.description}',
        notificationDetails: _details(style, sound),
      );
      return true;
    } catch (e) {
      debugPrint('Could not show the test notification: $e');
      return false;
    }
  }

  @override
  Future<void> sync(List<Task> tasks) {
    // Run one sync at a time so overlapping updates can't interleave.
    return _queue = _queue.then((_) => _sync(tasks)).catchError((Object e) {
      debugPrint('Could not schedule reminders: $e');
    });
  }

  Future<void> _sync(List<Task> tasks) async {
    await _plugin.cancelAllPendingNotifications();

    final alerts = planAlerts(tasks, DateTime.now());
    final exact = await _android?.canScheduleExactNotifications() ?? true;
    final mode = exact
        ? fln.AndroidScheduleMode.exactAllowWhileIdle
        : fln.AndroidScheduleMode.inexactAllowWhileIdle;

    for (final a in alerts.take(_maxPending)) {
      await _plugin.zonedSchedule(
        id: a.id,
        title: a.title,
        body: a.body,
        scheduledDate: tz.TZDateTime.from(a.at, tz.UTC),
        notificationDetails: _details(a.style, a.sound),
        androidScheduleMode: mode,
      );
    }
  }
}
