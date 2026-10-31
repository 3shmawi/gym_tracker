import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/settings/domain/entities/app_settings.dart';
import 'package:gym_tracker/features/settings/domain/repositories/settings_repository.dart';
import 'package:gym_tracker/features/settings/presentation/settings_controller.dart';
import 'package:mocktail/mocktail.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository;

void main() {
  late _MockSettingsRepository repository;
  late ProviderContainer container;

  setUpAll(() => registerFallbackValue(const AppSettings()));

  setUp(() {
    repository = _MockSettingsRepository();
    when(() => repository.load()).thenReturn(const AppSettings());
    when(() => repository.save(any())).thenAnswer((_) async {});
    container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
  });

  group(SettingsController, () {
    test('starts with the stored settings', () {
      expect(container.read(settingsControllerProvider), const AppSettings());
    });

    test('setThemeMode updates state and persists it', () {
      container
          .read(settingsControllerProvider.notifier)
          .setThemeMode(ThemeMode.dark);

      expect(
        container.read(settingsControllerProvider).themeMode,
        ThemeMode.dark,
      );
      verify(
        () => repository.save(const AppSettings(themeMode: ThemeMode.dark)),
      ).called(1);
    });

    test('setLocale updates state', () {
      container
          .read(settingsControllerProvider.notifier)
          .setLocale(const Locale('ar'));

      expect(
        container.read(settingsControllerProvider).locale,
        const Locale('ar'),
      );
    });

    test('does nothing when the value did not change', () {
      container
          .read(settingsControllerProvider.notifier)
          .setThemeMode(ThemeMode.system);

      verifyNever(() => repository.save(any()));
    });
  });
}
