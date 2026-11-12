import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
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

      // Each row shows its value and opens a sheet to pick (board 4).
      expect(find.text(l10nEn.settingsThemeSystem), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings_theme')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10nEn.settingsThemeDark));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_language')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10nEn.languageArabic));
      await tester.pumpAndSettle();

      expect(themeMode, ThemeMode.dark);
      expect(locale, const Locale('ar'));
    });

    testWidgets('closing a choice sheet changes nothing', (tester) async {
      var changes = 0;
      await tester.pumpApp(
        SettingsView(
          settings: const AppSettings(themeMode: ThemeMode.light),
          onLocaleChanged: (_) => changes++,
          onThemeModeChanged: (_) => changes++,
        ),
      );
      expect(find.text(l10nEn.settingsThemeLight), findsOneWidget);
      await tester.tap(find.byKey(const Key('settings_theme')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(changes, 0);
    });

    testWidgets('the version reads left to right in Arabic', (tester) async {
      await tester.pumpApp(
        SettingsView(
          settings: const AppSettings(),
          onLocaleChanged: (_) {},
          onThemeModeChanged: (_) {},
        ),
        locale: const Locale('ar'),
      );
      await tester.pumpAndSettle();
      final text = tester.widget<Text>(
        find.byKey(const Key('settings_version')),
      );
      expect(text.textDirection, TextDirection.ltr);
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

    testWidgets('the pose check row shows only when it is allowed', (
      tester,
    ) async {
      var opened = 0;
      Widget settings({VoidCallback? onOpenMoveCheck}) => SettingsView(
        settings: const AppSettings(),
        onLocaleChanged: (_) {},
        onThemeModeChanged: (_) {},
        onOpenMoveCheck: onOpenMoveCheck,
      );
      await tester.pumpApp(settings());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings_move_check')), findsNothing);

      await tester.pumpApp(settings(onOpenMoveCheck: () => opened++));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('settings_move_check')));
      await tester.tap(find.text(l10nEn.settingsMoveCheck));
      expect(opened, 1);
    });

    testWidgets('privacy policy and terms are always one tap away', (
      tester,
    ) async {
      final opened = <String>[];
      await tester.pumpApp(
        SettingsView(
          settings: const AppSettings(),
          onLocaleChanged: (_) {},
          onThemeModeChanged: (_) {},
          onOpenPrivacy: () => opened.add('privacy'),
          onOpenTerms: () => opened.add('terms'),
        ),
      );
      await tester.pumpAndSettle();
      for (final key in ['settings_privacy', 'settings_terms']) {
        await tester.ensureVisible(find.byKey(Key(key)));
        await tester.tap(find.byKey(Key(key)));
      }
      expect(opened, ['privacy', 'terms']);
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

      await tester.tap(find.byKey(const Key('settings_theme')));
      await tester.pumpAndSettle();
      final light = tester.widget<AppChoiceRow>(
        find.widgetWithText(AppChoiceRow, l10nEn.settingsThemeLight),
      );
      final dark = tester.widget<AppChoiceRow>(
        find.widgetWithText(AppChoiceRow, l10nEn.settingsThemeDark),
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
