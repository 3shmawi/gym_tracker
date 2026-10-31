# Feature: settings (language & theme)

## What it does
Lets the user choose the app language (device default, English, Arabic) and
theme (system, light, dark). Choices apply instantly and are saved on the
device. Arabic switches the whole UI to right-to-left.

## Architecture (layered, state: riverpod)
- Model: `lib/features/settings/domain/entities/app_settings.dart`
- Repository: `lib/features/settings/domain/repositories/settings_repository.dart` (SharedPreferences)
- State holder: `lib/features/settings/presentation/` (Riverpod (Notifier))
- UI: `settings_view.dart` is pure UI (state in, callbacks out);
  `settings_page.dart` connects it to the state holder.
- Route: `/settings` (`AppRoutes.settings`).

## Tests
- Repository: `test/features/settings/data/`
- State holder: `test/features/settings/presentation/`
- View: `test/features/settings/presentation/settings_view_test.dart`
- Integration: `integration_test/app_test.dart` (home → settings)
