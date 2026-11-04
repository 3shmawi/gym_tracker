import 'package:gym_tracker/features/workout/domain/services/rest_alarm.dart';

/// Records what the app asked of the notification, newest last.
class FakeRestAlarm implements RestAlarm {
  new({this.access = RestAlarmAccess.allowed});

  /// What [askOnce] answers the first time.
  RestAlarmAccess access;
  bool opened = false;

  int asked = 0;
  int openedSettings = 0;
  final calls = <String>[];

  /// The notice waiting to ring; null when none.
  RestAlarmNotice? scheduled;

  @override
  Future<RestAlarmAccess> askOnce() async =>
      asked++ == 0 ? access : RestAlarmAccess.alreadyAsked;

  @override
  Future<void> openOnTimeSettings() async => openedSettings++;

  @override
  Future<void> schedule(RestAlarmNotice notice) async {
    calls.add('schedule');
    scheduled = notice;
  }

  /// Notices rung on screen, oldest first.
  final rung = <RestAlarmNotice>[];

  @override
  Future<void> ringNow(RestAlarmNotice notice) async {
    calls.add('ring');
    rung.add(notice);
  }

  @override
  Future<void> cancel() async {
    calls.add('cancel');
    scheduled = null;
  }

  @override
  Future<bool> openedApp() async => opened;
}
