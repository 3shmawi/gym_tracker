import 'package:gym_tracker/features/settings/data/repositories/shared_prefs_settings_repository.dart';
import 'package:gym_tracker/features/settings/domain/repositories/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Composition root: the only place that knows which implementation backs
/// each domain interface. Add new repositories / services here.
abstract final class Dependencies {
  static late final SettingsRepository settingsRepository;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    settingsRepository = SharedPrefsSettingsRepository(prefs);
  }
}
