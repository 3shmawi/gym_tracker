import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/features/settings/domain/entities/app_settings.dart';
import 'package:gym_tracker/features/settings/domain/repositories/settings_repository.dart';

/// Override in tests: `settingsRepositoryProvider.overrideWithValue(fake)`.
final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => Dependencies.settingsRepository,
);

final settingsControllerProvider =
    NotifierProvider<SettingsController, AppSettings>(SettingsController.new);

/// Holds the current [AppSettings]; changes are applied immediately and
/// persisted in the background.
class SettingsController extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(settingsRepositoryProvider).load();

  void setLocale(Locale? locale) =>
      _update(state.copyWith(locale: () => locale));

  void setThemeMode(ThemeMode themeMode) =>
      _update(state.copyWith(themeMode: themeMode));

  void _update(AppSettings next) {
    if (next == state) return;
    state = next;
    unawaited(ref.read(settingsRepositoryProvider).save(next));
  }
}
