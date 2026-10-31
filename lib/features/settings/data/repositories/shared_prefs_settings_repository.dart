import 'package:flutter/material.dart';
import 'package:gym_tracker/features/settings/domain/entities/app_settings.dart';
import 'package:gym_tracker/features/settings/domain/repositories/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [SettingsRepository] backed by SharedPreferences.
class SharedPrefsSettingsRepository implements SettingsRepository {
  new(this._prefs);

  final SharedPreferences _prefs;

  static const _localeKey = 'settings.locale';
  static const _themeModeKey = 'settings.theme_mode';

  @override
  AppSettings load() {
    final languageCode = _prefs.getString(_localeKey);
    final themeModeName = _prefs.getString(_themeModeKey);
    return AppSettings(
      locale: languageCode == null ? null : Locale(languageCode),
      themeMode:
          ThemeMode.values.asNameMap()[themeModeName] ?? ThemeMode.system,
    );
  }

  @override
  Future<void> save(AppSettings settings) async {
    final locale = settings.locale;
    if (locale == null) {
      await _prefs.remove(_localeKey);
    } else {
      await _prefs.setString(_localeKey, locale.languageCode);
    }
    await _prefs.setString(_themeModeKey, settings.themeMode.name);
  }
}
