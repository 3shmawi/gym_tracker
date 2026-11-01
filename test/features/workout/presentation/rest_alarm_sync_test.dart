import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/workout/domain/services/rest_alarm.dart';
import 'package:gym_tracker/features/workout/presentation/rest_alarm_sync.dart';

import '../../../helpers/fake_rest_alarm.dart';

class _Failing extends FakeRestAlarm {
  @override
  Future<void> schedule(RestAlarmNotice notice) => Future.error('platform');

  @override
  Future<RestAlarmAccess> askOnce() => Future.error('platform');
}

void main() {
  final now = DateTime(2026, 11, 2, 18);
  RestAlarmNotice notice({int seconds = 90, String body = 'Squat · set 2'}) =>
      RestAlarmNotice(
        at: now.add(Duration(seconds: seconds)),
        title: 'Rest over',
        body: body,
        channelName: 'Rest timer',
      );

  late FakeRestAlarm alarm;
  late RestAlarmSync sync;
  setUp(() {
    alarm = FakeRestAlarm();
    sync = RestAlarmSync(alarm, now: () => now);
  });

  test('in front: nothing rings (the screen counts down itself)', () async {
    sync
      ..lifecycle(AppLifecycleState.resumed)
      ..rest(notice());
    await sync.idle;
    expect(alarm.scheduled, isNull);
  });

  test('locked or in the background during a rest: scheduled', () async {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      sync
        ..lifecycle(AppLifecycleState.resumed)
        ..rest(notice())
        ..lifecycle(state);
      await sync.idle;
      expect(alarm.scheduled, notice(), reason: '$state');
    }
  });

  test('back in front: removed', () async {
    sync
      ..rest(notice())
      ..lifecycle(AppLifecycleState.paused)
      ..lifecycle(AppLifecycleState.resumed);
    await sync.idle;
    expect(alarm.scheduled, isNull);
  });

  test('+15 s moves it; skip, log or finish remove it', () async {
    sync
      ..lifecycle(AppLifecycleState.paused)
      ..rest(notice())
      ..rest(notice(seconds: 105));
    await sync.idle;
    expect(alarm.scheduled!.at, now.add(const Duration(seconds: 105)));

    sync.rest(null);
    await sync.idle;
    expect(alarm.scheduled, isNull);
  });

  test('an edit that changes the next set updates the text', () async {
    sync
      ..lifecycle(AppLifecycleState.paused)
      ..rest(notice())
      ..rest(notice(body: 'Squat · set 3'));
    await sync.idle;
    expect(alarm.scheduled!.body, 'Squat · set 3');
  });

  test('the same notice twice is sent once', () async {
    sync
      ..lifecycle(AppLifecycleState.paused)
      ..rest(notice())
      ..rest(notice())
      ..lifecycle(AppLifecycleState.hidden);
    await sync.idle;
    expect(alarm.calls, ['cancel', 'schedule']);
  });

  test('first update cancels what a killed app left behind', () async {
    sync.lifecycle(AppLifecycleState.resumed);
    await sync.idle;
    expect(alarm.calls, ['cancel']);
  });

  test('a rest already over is not scheduled', () async {
    sync
      ..lifecycle(AppLifecycleState.paused)
      ..rest(notice(seconds: -1));
    await sync.idle;
    expect(alarm.scheduled, isNull);
  });

  test('closing the screen removes it, even when in the background', () async {
    sync
      ..lifecycle(AppLifecycleState.paused)
      ..rest(notice());
    await sync.close();
    expect(alarm.scheduled, isNull);
    expect(alarm.calls.last, 'cancel');

    sync.rest(notice());
    await sync.idle;
    expect(alarm.scheduled, isNull, reason: 'closed for good');
  });

  test('asks once, at the first rest', () async {
    expect(await sync.firstRest(), RestAlarmAccess.allowed);
    expect(await sync.firstRest(), RestAlarmAccess.alreadyAsked);
    expect(alarm.asked, 2);
  });

  test('platform errors never reach the workout', () async {
    final failing = RestAlarmSync(_Failing(), now: () => now)
      ..lifecycle(AppLifecycleState.paused)
      ..rest(notice());
    await expectLater(failing.idle, completes);
    expect(await failing.firstRest(), RestAlarmAccess.alreadyAsked);
  });
}
