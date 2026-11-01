import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/notifications/local_notifications.dart';

/// The plugin's method channel, answered like the phone would.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  late List<MethodCall> calls;
  late Map<String, Object?> answers;

  void on(TargetPlatform platform) {
    debugDefaultTargetPlatformOverride = platform;
    FlutterLocalNotificationsPlatform.instance =
        platform == TargetPlatform.android
        ? AndroidFlutterLocalNotificationsPlugin()
        : IOSFlutterLocalNotificationsPlugin();
  }

  setUp(() {
    calls = [];
    answers = {
      'initialize': true,
      'requestNotificationsPermission': true,
      'requestPermissions': true,
      'canScheduleExactNotifications': true,
      'getNotificationAppLaunchDetails': {'notificationLaunchedApp': false},
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return answers[call.method];
        });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  List<String> methods() => [for (final c in calls) c.method];

  Future<bool> scheduleIn(LocalNotifications n, Duration d) => n.schedule(
    id: 1,
    at: DateTime.now().add(d),
    title: 'Rest over',
    body: 'Squat · set 2',
    channelId: 'rest_timer',
    channelName: 'Rest timer',
  );

  group('Android', () {
    setUp(() => on(TargetPlatform.android));

    test('initialises once and never asks at start-up', () async {
      final n = LocalNotifications();
      await n.cancel(1);
      await n.cancel(1);
      expect(methods().where((m) => m == 'initialize'), hasLength(1));
      expect(methods(), isNot(contains('requestNotificationsPermission')));
      final init = calls.first.arguments as Map<Object?, Object?>;
      expect(init['defaultIcon'], LocalNotifications.androidIcon);
    });

    test('asks the Android 13+ way', () async {
      expect(await LocalNotifications().requestPermission(), isTrue);
      expect(methods(), contains('requestNotificationsPermission'));
    });

    test('schedules an exact alarm, at the given moment', () async {
      final n = LocalNotifications();
      expect(await scheduleIn(n, const Duration(seconds: 90)), isTrue);
      final call = calls.singleWhere((c) => c.method == 'zonedSchedule');
      final args = call.arguments as Map<Object?, Object?>;
      expect(args['title'], 'Rest over');
      expect(args['body'], 'Squat · set 2');
      final details = args['platformSpecifics']! as Map<Object?, Object?>;
      expect(details['scheduleMode'], 'exactAllowWhileIdle');
      expect(details['channelId'], 'rest_timer');
      expect(details['icon'], LocalNotifications.androidIcon);
    });

    test('no exact alarms (Android 14+ default): nothing scheduled', () async {
      answers['canScheduleExactNotifications'] = false;
      final n = LocalNotifications();
      expect(await n.canRingOnTime(), isFalse);
      expect(await scheduleIn(n, const Duration(seconds: 90)), isFalse);
      expect(methods(), isNot(contains('zonedSchedule')));
    });

    test('a moment already past is skipped', () async {
      final n = LocalNotifications();
      expect(await scheduleIn(n, const Duration(seconds: -5)), isFalse);
      expect(methods(), isNot(contains('zonedSchedule')));
    });

    test('settings, cancel and launch details', () async {
      final n = LocalNotifications();
      await n.openOnTimeSettings();
      await n.cancel(1);
      expect(await n.openedApp(), isFalse);
      answers['getNotificationAppLaunchDetails'] = {
        'notificationLaunchedApp': true,
      };
      expect(await n.openedApp(), isTrue);
      expect(
        methods(),
        containsAll(['requestExactAlarmsPermission', 'cancel']),
      );
    });
  });

  group('iOS', () {
    setUp(() => on(TargetPlatform.iOS));

    test('asks for alert and sound, not badge', () async {
      expect(await LocalNotifications().requestPermission(), isTrue);
      final ask = calls.singleWhere((c) => c.method == 'requestPermissions');
      final args = ask.arguments as Map<Object?, Object?>;
      expect(
        (args['alert'], args['sound'], args['badge']),
        (true, true, false),
      );
    });

    test('initialisation asks nothing', () async {
      await LocalNotifications().cancel(1);
      final init = calls.first.arguments as Map<Object?, Object?>;
      expect(init['requestAlertPermission'], isFalse);
      expect(init['requestSoundPermission'], isFalse);
      expect(init['requestBadgePermission'], isFalse);
    });

    test('always on time; no settings page to open', () async {
      final n = LocalNotifications();
      expect(await n.canRingOnTime(), isTrue);
      await n.openOnTimeSettings();
      expect(await scheduleIn(n, const Duration(seconds: 60)), isTrue);
      expect(methods(), isNot(contains('requestExactAlarmsPermission')));
    });
  });

  test('other platforms: does nothing', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final n = LocalNotifications();
    expect(await n.requestPermission(), isFalse);
    expect(await scheduleIn(n, const Duration(seconds: 60)), isFalse);
    expect(await n.openedApp(), isFalse);
    expect(calls, isEmpty);
  });
}
