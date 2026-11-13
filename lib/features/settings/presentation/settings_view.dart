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
    this.backup,
    this.onOpenAccount,
    this.onJoinGym,
    this.onOpenLicenses,
    this.onOpenPrivacy,
    this.onOpenTerms,
    this.onOpenMoveCheck,
    super.key,
  });

  final AppSettings settings;
  final ValueChanged<Locale?> onLocaleChanged;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  /// Opens the plan editor; the Workout section is hidden while null.
  final VoidCallback? onOpenPlan;

  /// The Backup card (`BackupCard`), or null while backup is not offered.
  final Widget? backup;

  /// "My account" for people signed in to a gym; else [onJoinGym] offers
  /// "Join your gym". Both null (gym accounts off) hides the section.
  final VoidCallback? onOpenAccount;
  final VoidCallback? onJoinGym;

  /// Opens the open-source licenses page (fonts, exercise pictures); the row
  /// is hidden while null.
  final VoidCallback? onOpenLicenses;

  /// The privacy policy and the terms on the website: always one tap away
  /// (YouTube API Services Developer Policies III.A).
  final VoidCallback? onOpenPrivacy;
  final VoidCallback? onOpenTerms;

  /// The pose check for testers (null in prod builds and with the
  /// `move_games_debug` flag off).
  final VoidCallback? onOpenMoveCheck;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final languageCode = settings.locale?.languageCode;
    final languages = <(String, Locale?)>[
      (l10n.settingsLanguageSystem, null),
      (l10n.languageEnglish, const Locale('en')),
      (l10n.languageArabic, const Locale('ar')),
    ];
    final languageIndex = switch (languageCode) {
      'en' => 1,
      'ar' => 2,
      _ => 0,
    };
    String themeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.system => l10n.settingsThemeSystem,
      ThemeMode.light => l10n.settingsThemeLight,
      ThemeMode.dark => l10n.settingsThemeDark,
    };
    return AppScaffold(
      title: l10n.settingsTitle,
      // Grouped cards of compact rows, the value at the end (design board
      // 4: the familiar iOS settings layout, readable on glass).
      body: ListView(
        padding: EdgeInsetsDirectional.fromSTEB(
          AppDimens.md,
          0,
          AppDimens.md,
          AppDimens.xl,
        ),
        children: [
          if (onOpenPlan != null) ...[
            SettingsSectionHeader(l10n.settingsWorkout),
            SettingsGroup(
              children: [
                SettingsRow(
                  key: const Key('settings_plan'),
                  label: l10n.planTitle,
                  icon: Icons.format_list_bulleted,
                  onTap: onOpenPlan,
                ),
              ],
            ),
          ],
          ?backup,
          SettingsSectionHeader(l10n.settingsAppearance),
          SettingsGroup(
            children: [
              SettingsRow(
                key: const Key('settings_language'),
                label: l10n.settingsLanguage,
                icon: Icons.translate,
                value: languages[languageIndex].$1,
                onTap: () async {
                  final picked = await showSettingsChoice(
                    context: context,
                    title: l10n.settingsLanguage,
                    choices: [for (final l in languages) l.$1],
                    selected: languageIndex,
                  );
                  if (picked != null) onLocaleChanged(languages[picked].$2);
                },
              ),
              SettingsRow(
                key: const Key('settings_theme'),
                label: l10n.settingsTheme,
                icon: Icons.contrast,
                value: themeLabel(settings.themeMode),
                onTap: () async {
                  final picked = await showSettingsChoice(
                    context: context,
                    title: l10n.settingsTheme,
                    choices: [for (final m in ThemeMode.values) themeLabel(m)],
                    selected: settings.themeMode.index,
                  );
                  if (picked != null) {
                    onThemeModeChanged(ThemeMode.values[picked]);
                  }
                },
              ),
            ],
          ),
          if (onOpenAccount != null || onJoinGym != null) ...[
            SettingsSectionHeader(l10n.settingsAccount),
            SettingsGroup(
              children: [
                if (onOpenAccount != null)
                  SettingsRow(
                    key: const Key('settings_account'),
                    label: l10n.settingsMyAccount,
                    icon: Icons.account_circle_outlined,
                    onTap: onOpenAccount,
                  )
                else
                  SettingsRow(
                    key: const Key('settings_join_gym'),
                    label: l10n.settingsJoinGym,
                    icon: Icons.qr_code_scanner,
                    onTap: onJoinGym,
                  ),
              ],
            ),
          ],
          SettingsSectionHeader(l10n.settingsAbout),
          SettingsGroup(
            children: [
              const SettingsVersionTile(),
              if (onOpenPrivacy != null)
                SettingsRow(
                  key: const Key('settings_privacy'),
                  label: l10n.legalPrivacy,
                  icon: Icons.privacy_tip_outlined,
                  onTap: onOpenPrivacy,
                ),
              if (onOpenTerms != null)
                SettingsRow(
                  key: const Key('settings_terms'),
                  label: l10n.legalTerms,
                  icon: Icons.gavel_outlined,
                  onTap: onOpenTerms,
                ),
              if (onOpenLicenses != null)
                SettingsRow(
                  key: const Key('settings_licenses'),
                  label: l10n.settingsLicenses,
                  icon: Icons.description_outlined,
                  onTap: onOpenLicenses,
                ),
              if (onOpenMoveCheck != null)
                SettingsRow(
                  key: const Key('settings_move_check'),
                  label: l10n.settingsMoveCheck,
                  icon: Icons.accessibility_new_rounded,
                  onTap: onOpenMoveCheck,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
