import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/settings/domain/entities/app_settings.dart';
import 'package:gym_tracker/features/settings/presentation/settings_view.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';

void main() {
  group(SettingsView, () {
    testWidgets('reports theme and language choices', (tester) async {
      ThemeMode? themeMode;
      Locale? locale;
      await tester.pumpApp(
        SettingsView(
          settings: const AppSettings(),
          onLocaleChanged: (value) => locale = value,
          onThemeModeChanged: (value) => themeMode = value,
        ),
      );

      await tester.tap(find.text(l10nEn.settingsThemeDark));
      await tester.tap(find.text(l10nEn.languageArabic));

      expect(themeMode, ThemeMode.dark);
      expect(locale, const Locale('ar'));
    });

    testWidgets('meets accessibility guidelines', (tester) async {
      await tester.pumpApp(
        SettingsView(
          settings: const AppSettings(),
          onLocaleChanged: (_) {},
          onThemeModeChanged: (_) {},
        ),
      );
      await tester.expectAccessible();
    });

    testWidgets('marks the current choices as selected', (tester) async {
      await tester.pumpApp(
        SettingsView(
          settings: const AppSettings(themeMode: ThemeMode.light),
          onLocaleChanged: (_) {},
          onThemeModeChanged: (_) {},
        ),
      );

      final light = tester.widget<ListTile>(
        find.widgetWithText(ListTile, l10nEn.settingsThemeLight),
      );
      final dark = tester.widget<ListTile>(
        find.widgetWithText(ListTile, l10nEn.settingsThemeDark),
      );
      expect(light.selected, isTrue);
      expect(dark.selected, isFalse);
    });
  });

  testWidgets('"Your plan" opens the plan editor', (tester) async {
    var opened = 0;
    await tester.pumpApp(
      SettingsView(
        settings: const AppSettings(),
        onLocaleChanged: (_) {},
        onThemeModeChanged: (_) {},
        onOpenPlan: () => opened++,
      ),
    );
    expect(find.text('Workout'), findsOneWidget);
    await tester.tap(find.byKey(const Key('settings_plan')));
    expect(opened, 1);
  });

  screenUiTests(
    'settings',
    () => SettingsView(
      settings: const AppSettings(),
      onLocaleChanged: (_) {},
      onThemeModeChanged: (_) {},
      onOpenPlan: () {},
    ),
  );
}
