import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/settings/domain/entities/app_settings.dart';
import 'package:gym_tracker/features/settings/presentation/widgets/settings_tiles.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// Language, theme and app version settings. Pure UI: state comes in,
/// changes go out through callbacks, so it works with any state-management
/// choice.
class SettingsView extends StatelessWidget {
  const new({
    required this.settings,
    required this.onLocaleChanged,
    required this.onThemeModeChanged,
    this.onOpenPlan,
    this.onOpenAccount,
    this.onJoinGym,
    this.onOpenLicenses,
    super.key,
  });

  final AppSettings settings;
  final ValueChanged<Locale?> onLocaleChanged;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  /// Opens the plan editor; the Workout section is hidden while null.
  final VoidCallback? onOpenPlan;

  /// "My account" for people signed in to a gym; else [onJoinGym] offers
  /// "Join your gym". Both null (gym accounts off) hides the section.
  final VoidCallback? onOpenAccount;
  final VoidCallback? onJoinGym;

  /// Opens the open-source licenses page (fonts, exercise pictures); the row
  /// is hidden while null.
  final VoidCallback? onOpenLicenses;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final languageCode = settings.locale?.languageCode;
    return AppScaffold(
      title: l10n.settingsTitle,
      // Grouped sections on cards: readable on any background (glass or
      // not) and the familiar iOS settings layout.
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: AppDimens.md),
        children: [
          if (onOpenPlan != null) ...[
            SettingsSectionHeader(l10n.settingsWorkout),
            AppCard(
              child: SettingsLinkTile(
                key: const Key('settings_plan'),
                label: l10n.planTitle,
                icon: Icons.format_list_bulleted,
                onTap: onOpenPlan!,
              ),
            ),
          ],
          if (onOpenAccount != null || onJoinGym != null) ...[
            SettingsSectionHeader(l10n.settingsAccount),
            AppCard(
              child: onOpenAccount != null
                  ? SettingsLinkTile(
                      key: const Key('settings_account'),
                      label: l10n.settingsMyAccount,
                      icon: Icons.account_circle_outlined,
                      onTap: onOpenAccount!,
                    )
                  : SettingsLinkTile(
                      key: const Key('settings_join_gym'),
                      label: l10n.settingsJoinGym,
                      icon: Icons.qr_code_scanner,
                      onTap: onJoinGym!,
                    ),
            ),
          ],
          SettingsSectionHeader(l10n.settingsLanguage),
          AppCard(
            child: Column(
              children: [
                SettingsChoiceTile(
                  label: l10n.settingsLanguageSystem,
                  selected: languageCode == null,
                  onTap: () => onLocaleChanged(null),
                ),
                SettingsChoiceTile(
                  label: l10n.languageEnglish,
                  selected: languageCode == 'en',
                  onTap: () => onLocaleChanged(const Locale('en')),
                ),
                SettingsChoiceTile(
                  label: l10n.languageArabic,
                  selected: languageCode == 'ar',
                  onTap: () => onLocaleChanged(const Locale('ar')),
                ),
              ],
            ),
          ),
          SettingsSectionHeader(l10n.settingsTheme),
          AppCard(
            child: Column(
              children: [
                for (final mode in ThemeMode.values)
                  SettingsChoiceTile(
                    label: switch (mode) {
                      ThemeMode.system => l10n.settingsThemeSystem,
                      ThemeMode.light => l10n.settingsThemeLight,
                      ThemeMode.dark => l10n.settingsThemeDark,
                    },
                    selected: settings.themeMode == mode,
                    onTap: () => onThemeModeChanged(mode),
                  ),
              ],
            ),
          ),
          SettingsSectionHeader(l10n.settingsAbout),
          AppCard(
            child: Column(
              children: [
                const SettingsVersionTile(),
                if (onOpenLicenses != null)
                  SettingsLinkTile(
                    key: const Key('settings_licenses'),
                    label: l10n.settingsLicenses,
                    icon: Icons.description_outlined,
                    onTap: onOpenLicenses!,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
