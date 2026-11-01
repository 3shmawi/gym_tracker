import 'package:gym_tracker/core/notifications/local_notifications.dart';
import 'package:gym_tracker/core/theme/app_colors.dart';
import 'package:gym_tracker/features/workout/domain/services/rest_alarm.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [RestAlarm] with a local notification. Remembers that it asked, so the
/// member sees the system prompt (and the Android "on time" sheet) once.
class NotificationRestAlarm implements RestAlarm {
  const new(this._notifications, this._prefs);

  final LocalNotifications _notifications;
  final SharedPreferences _prefs;

  /// One rest at a time: a new one replaces the old.
  static const notificationId = 1;
  static const channelId = 'rest_timer';
  static const askedKey = 'rest_alarm.asked';

  @override
  Future<RestAlarmAccess> askOnce() async {
    // `get`, not `getBool`: a wrong stored type must not throw.
    if (_prefs.get(askedKey) == true) return RestAlarmAccess.alreadyAsked;
    await _prefs.setBool(askedKey, true);
    if (!await _notifications.requestPermission()) {
      return RestAlarmAccess.denied;
    }
    return await _notifications.canRingOnTime()
        ? RestAlarmAccess.allowed
        : RestAlarmAccess.needsOnTime;
  }

  @override
  Future<void> openOnTimeSettings() => _notifications.openOnTimeSettings();

  @override
  Future<void> schedule(RestAlarmNotice notice) => _notifications.schedule(
    id: notificationId,
    at: notice.at,
    title: notice.title,
    body: notice.body,
    channelId: channelId,
    channelName: notice.channelName,
    color: AppColors.primary,
  );

  @override
  Future<void> cancel() => _notifications.cancel(notificationId);

  @override
  Future<bool> openedApp() => _notifications.openedApp();
}
