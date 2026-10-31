import 'package:gym_tracker/core/backend/backend.dart';
import 'package:gym_tracker/features/settings/data/repositories/shared_prefs_settings_repository.dart';
import 'package:gym_tracker/features/settings/domain/repositories/settings_repository.dart';
import 'package:gym_tracker/features/workout/data/datasources/workout_database.dart';
import 'package:gym_tracker/features/workout/data/datasources/workout_remote.dart';
import 'package:gym_tracker/features/workout/data/repositories/offline_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Composition root: the only place that knows which implementation backs
/// each domain interface. Add new repositories / services here.
abstract final class Dependencies {
  static late final SettingsRepository settingsRepository;
  static late final WorkoutRepository workoutRepository;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    settingsRepository = SharedPrefsSettingsRepository(prefs);

    const uuid = Uuid();
    workoutRepository = OfflineWorkoutRepository(
      db: WorkoutDatabase(),
      remote: SupabaseWorkoutRemote(
        Backend.isConfigured ? Backend.client : null,
      ),
      newId: uuid.v4,
    );
  }
}
