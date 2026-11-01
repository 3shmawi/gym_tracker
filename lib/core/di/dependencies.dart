import 'package:gym_tracker/core/notifications/local_notifications.dart';
import 'package:gym_tracker/features/settings/data/repositories/shared_prefs_settings_repository.dart';
import 'package:gym_tracker/features/settings/domain/repositories/settings_repository.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/data/services/notification_rest_alarm.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/services/rest_alarm.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Composition root: the only place that knows which implementation backs
/// each domain interface. Add new repositories / services here.
abstract final class Dependencies {
  static late SettingsRepository settingsRepository;
  static late WorkoutRepository workoutRepository;

  /// Silent until [init] runs (and in widget tests).
  static RestAlarm restAlarm = const SilentRestAlarm();

  /// Safe to call again (integration tests start the app more than once).
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    settingsRepository = SharedPrefsSettingsRepository(prefs);
    workoutRepository = LocalWorkoutRepository(prefs);
    restAlarm = NotificationRestAlarm(LocalNotifications(), prefs);
  }
}
