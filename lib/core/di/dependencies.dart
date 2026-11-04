import 'package:gym_tracker/core/backend/backend.dart';
import 'package:gym_tracker/core/captcha/turnstile_captcha.dart';
import 'package:gym_tracker/core/config/env.dart';
import 'package:gym_tracker/core/legal/legal.dart';
import 'package:gym_tracker/core/media/video_info.dart';
import 'package:gym_tracker/core/notifications/local_notifications.dart';
import 'package:gym_tracker/features/gym/data/datasources/secret_store.dart';
import 'package:gym_tracker/features/gym/data/datasources/secure_install_id_store.dart';
import 'package:gym_tracker/features/gym/data/repositories/in_memory_gym_local_repository.dart';
import 'package:gym_tracker/features/gym/data/repositories/in_memory_gym_media.dart';
import 'package:gym_tracker/features/gym/data/repositories/in_memory_plan_sync.dart';
import 'package:gym_tracker/features/gym/data/repositories/in_memory_solo_import.dart';
import 'package:gym_tracker/features/gym/data/repositories/prefs_gym_local_repository.dart';
import 'package:gym_tracker/features/gym/data/repositories/prefs_gym_media_store.dart';
import 'package:gym_tracker/features/gym/data/repositories/prefs_gym_plan_store.dart';
import 'package:gym_tracker/features/gym/data/repositories/prefs_solo_import_store.dart';
import 'package:gym_tracker/features/gym/data/repositories/supabase_account_repository.dart';
import 'package:gym_tracker/features/gym/data/repositories/supabase_gym_media_repository.dart';
import 'package:gym_tracker/features/gym/data/repositories/supabase_gym_plan_repository.dart';
import 'package:gym_tracker/features/gym/data/repositories/supabase_gym_repository.dart';
import 'package:gym_tracker/features/gym/data/repositories/supabase_picture_catalog_repository.dart';
import 'package:gym_tracker/features/gym/data/repositories/supabase_session_uploader.dart';
import 'package:gym_tracker/features/gym/data/repositories/supabase_solo_import_repository.dart';
import 'package:gym_tracker/features/gym/data/repositories/unconfigured_gym_repositories.dart';
import 'package:gym_tracker/features/gym/domain/repositories/account_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_local_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_media_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_plan_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/picture_catalog_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/session_outbox.dart';
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

  /// Whether the member agreed to the Terms and Privacy Policy.
  static ConsentStore consentStore = const AcceptedConsentStore();
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

  /// The gym's plan (server + the phone's copy) and the queue of finished
  /// workouts waiting to be uploaded.
  static GymPlanRepository gymPlanRepository =
      const UnconfiguredGymPlanRepository();
  static GymPlanStore gymPlanStore = InMemoryGymPlanStore();
  static SessionOutbox sessionOutbox = InMemorySessionOutbox();
  static SessionUploader sessionUploader = const UnconfiguredSessionUploader();

  /// What the gym chose to show on exercise screens (server + the phone's
  /// copy).
  static GymMediaRepository gymMediaRepository =
      const UnconfiguredGymMediaRepository();
  static GymMediaStore gymMediaStore = InMemoryGymMediaStore();

  /// The shared picture library, searched by solo members.
  static PictureCatalogRepository pictureCatalog =
      const UnconfiguredPictureCatalogRepository();

  /// The phone's copy of video titles (null until [init], and in widget
  /// tests: the card then only knows what oEmbed answers).
  static VideoInfoStore? videoInfoStore;

  /// Silent until [init] runs (and in widget tests).
  static RestAlarm restAlarm = const SilentRestAlarm();

  /// Safe to call again (integration tests start the app more than once).
  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    settingsRepository = SharedPrefsSettingsRepository(prefs);
    consentStore = PrefsConsentStore(prefs);
    workoutRepository = LocalWorkoutRepository(prefs);
    restAlarm = NotificationRestAlarm(LocalNotifications(), prefs);
    gymLocalRepository = PrefsGymLocalRepository(prefs);
    soloImportStore = PrefsSoloImportStore(prefs);
    gymPlanStore = PrefsGymPlanStore(prefs);
    gymMediaStore = PrefsGymMediaStore(prefs);
    videoInfoStore = VideoInfoStore(prefs);
    sessionOutbox = PrefsSessionOutbox(prefs);
    if (Backend.isConfigured && Backend.isReady) {
      gymRepository = SupabaseGymRepository(
        Backend.client,
        SecureInstallIdStore(const FlutterSecretStore()),
        captchaToken: Env.turnstileSiteKey.isEmpty
            ? null
            : const TurnstileCaptcha(siteKey: Env.turnstileSiteKey).token,
      );
      accountRepository = SupabaseAccountRepository(Backend.client);
      soloImportRepository = SupabaseSoloImportRepository(Backend.client);
      gymPlanRepository = SupabaseGymPlanRepository(Backend.client);
      sessionUploader = SupabaseSessionUploader(Backend.client);
      gymMediaRepository = SupabaseGymMediaRepository(Backend.client);
      pictureCatalog = SupabasePictureCatalogRepository(Backend.client);
    } else {
      gymRepository = const UnconfiguredGymRepository();
      accountRepository = const UnconfiguredAccountRepository();
      soloImportRepository = const UnconfiguredSoloImportRepository();
      gymPlanRepository = const UnconfiguredGymPlanRepository();
      sessionUploader = const UnconfiguredSessionUploader();
      gymMediaRepository = const UnconfiguredGymMediaRepository();
      pictureCatalog = const UnconfiguredPictureCatalogRepository();
    }
  }
}
