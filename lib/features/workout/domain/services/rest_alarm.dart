import 'package:meta/meta.dart';

/// What the member answered when asked, at their first rest, whether the
/// app may tell them when a rest is over.
enum RestAlarmAccess {
  /// Notifications on, and they can ring on time.
  allowed,

  /// Notifications off (or the member said no).
  denied,

  /// Notifications on, but Android 14+ needs "Alarms & reminders" turned on
  /// for them to ring on time; until then they ring late (inexact).
  needsOnTime,

  /// Asked before; nothing to show.
  alreadyAsked,
}

/// The notification shown when a rest ends while the app isn't on screen.
@immutable
class RestAlarmNotice {
  const new({
    required this.at,
    required this.title,
    required this.body,
    required this.channelName,
  });

  /// When the rest ends.
  final DateTime at;

  /// "Rest over".
  final String title;

  /// "Squat · set 2": the set to do next.
  final String body;

  /// The Android notification channel's name ("Rest timer").
  final String channelName;

  @override
  bool operator ==(Object other) =>
      other is RestAlarmNotice &&
      other.at == at &&
      other.title == title &&
      other.body == body &&
      other.channelName == channelName;

  @override
  int get hashCode => Object.hash(at, title, body, channelName);
}

/// Rings when a rest is over: scheduled while the phone is locked or the app
/// is in the background, and right away when it ends on screen. Local
/// notifications (nothing leaves the phone); wired in
/// `core/di/dependencies.dart`.
abstract interface class RestAlarm {
  /// Asks for permission the first time only (the first rest, never at
  /// launch); later calls answer [RestAlarmAccess.alreadyAsked].
  Future<RestAlarmAccess> askOnce();

  /// Opens the system page where "Alarms & reminders" is turned on.
  Future<void> openOnTimeSettings();

  /// Schedules [notice], replacing the one scheduled before.
  Future<void> schedule(RestAlarmNotice notice);

  /// Rings [notice] now (the rest ended while the app is on screen).
  Future<void> ringNow(RestAlarmNotice notice);

  /// Removes the scheduled (or shown) notice, if any.
  Future<void> cancel();

  /// True when the app was opened by tapping the notice.
  Future<bool> openedApp();
}

/// Does nothing: before start-up has run, and in tests that don't care.
class SilentRestAlarm implements RestAlarm {
  const new();

  @override
  Future<RestAlarmAccess> askOnce() async => RestAlarmAccess.alreadyAsked;

  @override
  Future<void> openOnTimeSettings() async {}

  @override
  Future<void> schedule(RestAlarmNotice notice) async {}

  @override
  Future<void> ringNow(RestAlarmNotice notice) async {}

  @override
  Future<void> cancel() async {}

  @override
  Future<bool> openedApp() async => false;
}
