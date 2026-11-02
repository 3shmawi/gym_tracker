import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/settings/domain/entities/app_settings.dart';
import 'package:gym_tracker/features/settings/presentation/widgets/settings_tiles.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// Language and theme settings. Pure UI: state comes in, changes go out
/// through callbacks, so it works with any state-management choice.
class SettingsView extends StatelessWidget {
  const new({
    required this.settings,
    required this.onLocaleChanged,
    required this.onThemeModeChanged,
    this.onOpenPlan,
    super.key,
  });

  final AppSettings settings;
  final ValueChanged<Locale?> onLocaleChanged;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  /// Opens the plan editor; the Workout section is hidden while null.
  final VoidCallback? onOpenPlan;

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
        ],
      ),
    );
  }
}
