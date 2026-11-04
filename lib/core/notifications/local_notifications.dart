import 'dart:async';
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Notifications scheduled on the phone itself (flutter_local_notifications
/// 22.3.3, checked 2026-11-01): nothing goes through a server, no token.
///
/// Asks for nothing at start-up: [requestPermission] is called by a feature
/// at the moment the notification makes sense (Apple: "make the request in
/// a context that helps people understand why").
class LocalNotifications {
  new({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<bool>? _ready;

  /// White silhouette of the logo (`android/app/src/main/res/drawable-*`),
  /// kept from R8 by `res/raw/keep.xml`.
  static const androidIcon = 'ic_stat_rest';

  bool get _android => defaultTargetPlatform == TargetPlatform.android;
  bool get _ios => defaultTargetPlatform == TargetPlatform.iOS;

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _iosPlugin => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  /// Once; never asks for permission (the three iOS flags are false).
  Future<bool> _init() => _ready ??= () async {
    if (!_android && !_ios) return false;
    final ok = await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(androidIcon),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    return ok ?? false;
  }();

  /// Shows the system prompt the first time (iOS; Android 13+), else just
  /// answers. True when notifications may be shown.
  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    if (_android) {
      return await _androidPlugin?.requestNotificationsPermission() ?? false;
    }
    return await _iosPlugin?.requestPermissions(alert: true, sound: true) ??
        false;
  }

  /// Android 12+: exact alarms need "Alarms & reminders", off by default
  /// for new installs on Android 14+. An inexact alarm can be 10 minutes to
  /// an hour late (developer.android.com, "Schedule alarms"), too late for
  /// a rest. Always true on iOS.
  Future<bool> canRingOnTime() async {
    if (!await _init()) return false;
    if (!_android) return true;
    return await _androidPlugin?.canScheduleExactNotifications() ?? false;
  }

  /// Android: opens "Alarms & reminders" for this app.
  Future<void> openOnTimeSettings() async {
    if (!_android || !await _init()) return;
    await _androidPlugin?.requestExactAlarmsPermission();
  }

  /// Shows [title] / [body] at [at]. Skipped (false) when [at] has passed.
  /// On Android without "Alarms & reminders" it is scheduled inexact
  /// (`inexactAllowWhileIdle`): it may be late, but it still rings, which
  /// beats never ringing (field test 2026-11-03).
  Future<bool> schedule({
    required int id,
    required DateTime at,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    Color? color,
  }) async {
    final onTime = await canRingOnTime();
    if (!await _init()) return false;
    final when = tz.TZDateTime.from(at, tz.UTC);
    if (!when.isAfter(tz.TZDateTime.now(tz.UTC))) return false;
    await _plugin.zonedSchedule(
      id: id,
      scheduledDate: when,
      title: title,
      body: body,
      androidScheduleMode: onTime
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: _details(channelId, channelName, color),
    );
    return true;
  }

  /// Rings now while the app is on screen: the sound (and on Android a
  /// short heads-up that goes away by itself). On iOS no banner covers
  /// the screen: sound only.
  Future<bool> ringNow({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    Color? color,
  }) async {
    if (!await _init()) return false;
    await _plugin.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: _details(
        channelId,
        channelName,
        color,
        inFront: true,
      ),
    );
    return true;
  }

  static NotificationDetails _details(
    String channelId,
    String channelName,
    Color? color, {
    bool inFront = false,
  }) => NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      icon: androidIcon,
      color: color,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      visibility: NotificationVisibility.public,
      timeoutAfter: inFront ? ringTimeout.inMilliseconds : null,
    ),
    iOS: DarwinNotificationDetails(
      presentAlert: !inFront,
      presentBanner: !inFront,
      presentList: !inFront,
      presentSound: true,
      threadIdentifier: channelId,
      interruptionLevel: InterruptionLevel.active,
    ),
  );

  /// How long the in-app ring stays in the Android notification shade.
  static const ringTimeout = Duration(seconds: 5);

  /// Removes notification [id], scheduled or already shown.
  Future<void> cancel(int id) async {
    if (!await _init()) return;
    await _plugin.cancel(id: id);
  }

  /// True when tapping one of this app's notifications opened the app. The
  /// payload is never read, so a notification can't steer the app.
  Future<bool> openedApp() async {
    if (!await _init()) return false;
    final details = await _plugin.getNotificationAppLaunchDetails();
    return details?.didNotificationLaunchApp ?? false;
  }
}
