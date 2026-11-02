import 'package:gym_tracker/core/backend/backend.dart';
import 'package:gym_tracker/core/notifications/local_notifications.dart';
import 'package:gym_tracker/features/gym/data/datasources/secret_store.dart';
import 'package:gym_tracker/features/gym/data/datasources/secure_install_id_store.dart';
import 'package:gym_tracker/features/gym/data/repositories/in_memory_gym_local_repository.dart';
import 'package:gym_tracker/features/gym/data/repositories/in_memory_solo_import.dart';
import 'package:gym_tracker/features/gym/data/repositories/prefs_gym_local_repository.dart';
import 'package:gym_tracker/features/gym/data/repositories/prefs_solo_import_store.dart';
import 'package:gym_tracker/features/gym/data/repositories/supabase_account_repository.dart';
import 'package:gym_tracker/features/gym/data/repositories/supabase_gym_repository.dart';
import 'package:gym_tracker/features/gym/data/repositories/supabase_solo_import_repository.dart';
import 'package:gym_tracker/features/gym/data/repositories/unconfigured_gym_repositories.dart';
import 'package:gym_tracker/features/gym/domain/repositories/account_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_local_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/solo_import_repository.dart';
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

  /// Gym accounts. Until [init] runs, in widget tests and without Supabase
  /// values in the env file, joining fails with "offline" and nobody is
  /// signed in.
  static GymRepository gymRepository = const UnconfiguredGymRepository();
  static AccountRepository accountRepository =
      const UnconfiguredAccountRepository();
  static GymLocalRepository gymLocalRepository = InMemoryGymLocalRepository();
  static SoloImportRepository soloImportRepository =
      const UnconfiguredSoloImportRepository();
  static SoloImportStore soloImportStore = InMemorySoloImportStore();

  /// Silent until [init] runs (and in widget tests).
  static RestAlarm restAlarm = const SilentRestAlarm();

  /// Safe to call again (integration tests start the app more than once).
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    settingsRepository = SharedPrefsSettingsRepository(prefs);
    workoutRepository = LocalWorkoutRepository(prefs);
    restAlarm = NotificationRestAlarm(LocalNotifications(), prefs);
    gymLocalRepository = PrefsGymLocalRepository(prefs);
    soloImportStore = PrefsSoloImportStore(prefs);
    if (Backend.isConfigured && Backend.isReady) {
      gymRepository = SupabaseGymRepository(
        Backend.client,
        SecureInstallIdStore(const FlutterSecretStore()),
      );
      accountRepository = SupabaseAccountRepository(Backend.client);
      soloImportRepository = SupabaseSoloImportRepository(Backend.client);
    } else {
      gymRepository = const UnconfiguredGymRepository();
      accountRepository = const UnconfiguredAccountRepository();
      soloImportRepository = const UnconfiguredSoloImportRepository();
    }
  }
}
