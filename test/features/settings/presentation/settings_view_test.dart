import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/settings/domain/entities/app_settings.dart';
import 'package:gym_tracker/features/settings/presentation/settings_view.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'app',
      packageName: 'com.example.app',
      version: '1.2.3',
      buildNumber: '45',
      buildSignature: '',
    );
  });

  group(SettingsView, () {
    testWidgets('shows the app version and build number', (tester) async {
      await tester.pumpApp(
        SettingsView(
          settings: const AppSettings(),
          onLocaleChanged: (_) {},
          onThemeModeChanged: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1.2.3 (45)'), findsOneWidget);
    });

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

    testWidgets('the licenses row opens the licenses page', (tester) async {
      var opened = 0;
      await tester.pumpApp(
        SettingsView(
          settings: const AppSettings(),
          onLocaleChanged: (_) {},
          onThemeModeChanged: (_) {},
          onOpenLicenses: () => opened++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byKey(const Key('settings_licenses')));
      await tester.tap(find.text(l10nEn.settingsLicenses));
      expect(opened, 1);
    });

    // Regression: in Arabic the "Your plan" arrow pointed right. The chevron
    // mirrors itself in RTL, and the row also swapped it for Arabic: two
    // flips. It must be the self-mirroring chevron_right in both languages,
    // so it points to the end edge (left in Arabic).
    for (final lang in ['en', 'ar']) {
      testWidgets('the "Your plan" arrow points to the end edge ($lang)', (
        tester,
      ) async {
        await tester.pumpApp(
          SettingsView(
            settings: const AppSettings(),
            onLocaleChanged: (_) {},
            onThemeModeChanged: (_) {},
            onOpenPlan: () {},
          ),
          locale: Locale(lang),
        );
        final arrow = find.byIcon(Icons.chevron_right);
        expect(arrow, findsWidgets);
        expect(find.byIcon(Icons.chevron_left), findsNothing);
        expect(Icons.chevron_right.matchTextDirection, isTrue);
        expect(
          Directionality.of(tester.element(arrow.first)),
          lang == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        );
      });
    }

    testWidgets('no licenses callback: no licenses row', (tester) async {
      await tester.pumpApp(
        SettingsView(
          settings: const AppSettings(),
          onLocaleChanged: (_) {},
          onThemeModeChanged: (_) {},
        ),
      );
      expect(find.byKey(const Key('settings_licenses')), findsNothing);
    });

    testWidgets('gym accounts off: no gym section', (tester) async {
      await tester.pumpApp(
        SettingsView(
          settings: const AppSettings(),
          onLocaleChanged: (_) {},
          onThemeModeChanged: (_) {},
        ),
      );
      expect(find.text(l10nEn.settingsAccount), findsNothing);
    });

    testWidgets('signed in: "My account"; signed out: "Join your gym"', (
      tester,
    ) async {
      var account = 0;
      await tester.pumpApp(
        SettingsView(
          settings: const AppSettings(),
          onLocaleChanged: (_) {},
          onThemeModeChanged: (_) {},
          onOpenAccount: () => account++,
        ),
      );
      await tester.tap(find.byKey(const Key('settings_account')));
      expect(account, 1);
      expect(find.byKey(const Key('settings_join_gym')), findsNothing);

      var joined = 0;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpApp(
        SettingsView(
          settings: const AppSettings(),
          onLocaleChanged: (_) {},
          onThemeModeChanged: (_) {},
          onJoinGym: () => joined++,
        ),
      );
      await tester.tap(find.byKey(const Key('settings_join_gym')));
      expect(joined, 1);
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
      onOpenLicenses: () {},
    ),
  );
}
