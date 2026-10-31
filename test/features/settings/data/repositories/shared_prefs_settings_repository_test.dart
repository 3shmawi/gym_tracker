import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/settings/data/repositories/shared_prefs_settings_repository.dart';
import 'package:gym_tracker/features/settings/domain/entities/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group(SharedPrefsSettingsRepository, () {
    Future<SharedPrefsSettingsRepository> create([
      Map<String, Object> values = const {},
    ]) async {
      SharedPreferences.setMockInitialValues(values);
      return SharedPrefsSettingsRepository(
        await SharedPreferences.getInstance(),
      );
    }

    test('returns defaults when nothing is stored', () async {
      final repository = await create();
      expect(repository.load(), const AppSettings());
    });

    test('saves and loads locale and theme mode', () async {
      final repository = await create();
      const settings = AppSettings(
        locale: Locale('ar'),
        themeMode: ThemeMode.dark,
      );

      await repository.save(settings);

      expect(repository.load(), settings);
    });

    test('clears the locale when following the device language', () async {
      final repository = await create({'settings.locale': 'ar'});

      await repository.save(const AppSettings());

      expect(repository.load().locale, isNull);
    });
  });
}
