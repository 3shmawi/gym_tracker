import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/notifications/local_notifications.dart';
import 'package:gym_tracker/core/theme/app_colors.dart';
import 'package:gym_tracker/features/workout/data/services/notification_rest_alarm.dart';
import 'package:gym_tracker/features/workout/domain/services/rest_alarm.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Notifications extends Mock implements LocalNotifications;

void main() {
  late _Notifications notifications;
  late SharedPreferences prefs;
  late NotificationRestAlarm alarm;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    notifications = _Notifications();
    alarm = NotificationRestAlarm(notifications, prefs);
    when(() => notifications.requestPermission()).thenAnswer((_) async => true);
    when(() => notifications.canRingOnTime()).thenAnswer((_) async => true);
  });

  group('askOnce', () {
    test('allowed, then never asks again', () async {
      expect(await alarm.askOnce(), RestAlarmAccess.allowed);
      expect(await alarm.askOnce(), RestAlarmAccess.alreadyAsked);
      verify(() => notifications.requestPermission()).called(1);
    });

    test('remembered across launches', () async {
      await alarm.askOnce();
      final again = NotificationRestAlarm(notifications, prefs);
      expect(await again.askOnce(), RestAlarmAccess.alreadyAsked);
    });

    test('denied', () async {
      when(() => notifications.requestPermission())
          .thenAnswer((_) async => false);
      expect(await alarm.askOnce(), RestAlarmAccess.denied);
      verifyNever(() => notifications.canRingOnTime());
    });

    test('Android 14+: on but not on time', () async {
      when(() => notifications.canRingOnTime()).thenAnswer((_) async => false);
      expect(await alarm.askOnce(), RestAlarmAccess.needsOnTime);
    });

    test('a hostile stored value counts as not asked', () async {
      SharedPreferences.setMockInitialValues({
        NotificationRestAlarm.askedKey: '<script>',
      });
      final hostile = NotificationRestAlarm(
        notifications,
        await SharedPreferences.getInstance(),
      );
      expect(await hostile.askOnce(), RestAlarmAccess.allowed);
    });
  });

  test('schedule: one id, the rest channel, the brand color', () async {
    when(
      () => notifications.schedule(
        id: any(named: 'id'),
        at: any(named: 'at'),
        title: any(named: 'title'),
        body: any(named: 'body'),
        channelId: any(named: 'channelId'),
        channelName: any(named: 'channelName'),
        color: any(named: 'color'),
      ),
    ).thenAnswer((_) async => true);
    final at = DateTime(2026, 11, 2, 18, 1, 30);
    await alarm.schedule(
      RestAlarmNotice(
        at: at,
        title: 'Rest over',
        body: 'Squat · set 2',
        channelName: 'Rest timer',
      ),
    );
    verify(
      () => notifications.schedule(
        id: NotificationRestAlarm.notificationId,
        at: at,
        title: 'Rest over',
        body: 'Squat · set 2',
        channelId: 'rest_timer',
        channelName: 'Rest timer',
        color: AppColors.primary,
      ),
    ).called(1);
  });

  test('cancel, settings and launch go to the plugin', () async {
    when(() => notifications.cancel(any())).thenAnswer((_) async {});
    when(() => notifications.openOnTimeSettings()).thenAnswer((_) async {});
    when(() => notifications.openedApp()).thenAnswer((_) async => true);
    await alarm.cancel();
    await alarm.openOnTimeSettings();
    expect(await alarm.openedApp(), isTrue);
    verify(() => notifications.cancel(NotificationRestAlarm.notificationId));
    verify(() => notifications.openOnTimeSettings());
  });
}
