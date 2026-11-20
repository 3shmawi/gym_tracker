# Feature: settings (language & theme)

## What it does
Lets the user choose the app language (device default, English, Arabic) and
theme (system, light, dark). Choices apply instantly and are saved on the
device. Arabic switches the whole UI to right-to-left.

<<<<<<< yours
Layout (2026-11-10, design "Azm — exercise pictures, workout pill,
how-to" board 4): groups of compact rows on cards, each group's name above
it in small muted bold. A row has an icon, its label at the start, the
current value at the end and a chevron when it opens something
(`SettingsGroup`, `SettingsRow`). **Appearance** holds **Language** and
**Theme**: each row shows the current choice and opens a sheet to pick
(`showSettingsChoice`, `AppChoiceRow`); closing the sheet changes nothing.
The version reads left to right in Arabic too (`1.2.3 (45)`, it came out
reversed before).

A **Workout** section at the top links to the plan editor ("Your plan",
`/plan`, see workout.md → Plan editor).

**About** shows the version and **Open-source licenses** (Flutter's licenses page:
the fonts' licenses and the exercise pictures' attributions,
`features/exercise_images.md`). The row is `SettingsView.onOpenLicenses`;
`SettingsPage` opens `showLicensePage`.
=======
Layout (the iOS settings look): groups of compact rows on cards, each
group's name above it in small muted bold (`SettingsSectionHeader`,
`SettingsGroup`, `SettingsRow` in `widgets/settings_tiles.dart`). A row has
an icon, its label at the start, the current value at the end and a chevron
(mirrors in RTL) when it opens something.
- **Appearance:** Language and Theme show the current choice and open a
  sheet to pick (`showSettingsChoice`, `SettingsChoiceRow` with a check).
  Closing the sheet changes nothing.
- **About:** the version (reads left to right in Arabic too, `1.2.3 (45)`),
  the privacy policy and terms (the `website/` pages, `LegalLinks` in
  `lib/core/legal/legal_links.dart`; hidden until the website has an https
  address) and open-source licenses (Flutter's licenses page).
>>>>>>> kit a50ee3f

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
- Legal links: `test/core/legal/legal_links_test.dart`
- Integration: `integration_test/app_test.dart` (home → settings → Arabic)
