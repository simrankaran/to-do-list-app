import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'
    as fln;
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../data/models.dart';

/// Schedules phone notifications for when a task's time slot starts and ends.
abstract interface class ReminderScheduler {
  /// Asks the user for permission to notify (and to use exact alarms).
  /// Returns false if notifications are off.
  Future<bool> requestPermission();

  /// Replaces every scheduled reminder with ones for [tasks].
  Future<void> sync(List<Task> tasks);
}

/// Used on platforms without local notifications (web, desktop) and in tests.
class NoReminders implements ReminderScheduler {
  const NoReminders();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> sync(List<Task> tasks) async {}
}

/// Local notifications via `flutter_local_notifications` (Android and iOS).
class LocalReminders implements ReminderScheduler {
  LocalReminders._();

  static final _plugin = fln.FlutterLocalNotificationsPlugin();

  /// iOS keeps at most 64 pending notifications; stay under it everywhere.
  static const _maxPending = 60;

  static const _details = fln.NotificationDetails(
    android: fln.AndroidNotificationDetails(
      'task_times',
      'Task start & end',
      channelDescription: "Alerts when a task's time slot starts and ends",
      importance: fln.Importance.high,
      priority: fln.Priority.high,
      category: fln.AndroidNotificationCategory.reminder,
    ),
    iOS: fln.DarwinNotificationDetails(presentAlert: true, presentSound: true),
  );

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
  Future<void> sync(List<Task> tasks) {
    // Run one sync at a time so overlapping updates can't interleave.
    return _queue = _queue.then((_) => _sync(tasks)).catchError((Object e) {
      debugPrint('Could not schedule reminders: $e');
    });
  }

  Future<void> _sync(List<Task> tasks) async {
    await _plugin.cancelAllPendingNotifications();

    final now = DateTime.now();
    final fmt = DateFormat.jm();
    final alerts = <({int id, DateTime at, String title, String body})>[];
    for (final t in tasks) {
      if (t.done || !t.remind || !t.hasTimeSlot) continue;
      final slot = '${fmt.format(t.startsAt!)} – ${fmt.format(t.endsAt!)}';
      final base = (t.id.hashCode & 0x3fffffff) * 2;
      if (t.startsAt!.isAfter(now)) {
        alerts.add((
          id: base,
          at: t.startsAt!,
          title: '▶ Time to start: ${t.title}',
          body: 'Scheduled $slot',
        ));
      }
      if (t.endsAt!.isAfter(now)) {
        alerts.add((
          id: base + 1,
          at: t.endsAt!,
          title: "⏹ Time's up: ${t.title}",
          body: 'Your $slot slot has ended. Mark it done?',
        ));
      }
    }
    alerts.sort((a, b) => a.at.compareTo(b.at));

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
        notificationDetails: _details,
        androidScheduleMode: mode,
      );
    }
  }
}
