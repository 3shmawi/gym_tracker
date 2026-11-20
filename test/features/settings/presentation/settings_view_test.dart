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

  Widget view({
    AppSettings settings = const AppSettings(),
    ValueChanged<Locale?>? onLocaleChanged,
    ValueChanged<ThemeMode>? onThemeModeChanged,
    VoidCallback? onOpenPrivacy,
    VoidCallback? onOpenTerms,
    VoidCallback? onOpenLicenses,
  }) => SettingsView(
    settings: settings,
    onLocaleChanged: onLocaleChanged ?? (_) {},
    onThemeModeChanged: onThemeModeChanged ?? (_) {},
    onOpenPrivacy: onOpenPrivacy,
    onOpenTerms: onOpenTerms,
    onOpenLicenses: onOpenLicenses,
  );

  group(SettingsView, () {
    testWidgets('shows the app version and build number, left to right', (
      tester,
    ) async {
      await tester.pumpApp(view());
      await tester.pumpAndSettle();

      expect(find.text('1.2.3 (45)'), findsOneWidget);
      final value = tester.widget<Text>(
        find.byKey(const Key('settings_version')),
      );
      expect(value.textDirection, TextDirection.ltr);
    });

    testWidgets('rows show the current choices', (tester) async {
      await tester.pumpApp(
        view(
          settings: const AppSettings(
            locale: Locale('en'),
            themeMode: ThemeMode.dark,
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('settings_language')),
          matching: find.text(l10nEn.languageEnglish),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('settings_theme')),
          matching: find.text(l10nEn.settingsThemeDark),
        ),
        findsOneWidget,
      );
    });

    testWidgets('picks a language and a theme from the sheet', (tester) async {
      Locale? locale = const Locale('x');
      ThemeMode? themeMode;
      await tester.pumpApp(
        view(
          onLocaleChanged: (value) => locale = value,
          onThemeModeChanged: (value) => themeMode = value,
        ),
      );

<<<<<<< yours
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
=======
      await tester.tap(find.byKey(const Key('settings_language')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_choice_2')));
      await tester.pumpAndSettle();
      expect(locale, const Locale('ar'));
      expect(find.byKey(const Key('settings_choice_2')), findsNothing);
>>>>>>> kit a50ee3f

      await tester.tap(find.byKey(const Key('settings_theme')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settings_choice_2')));
      await tester.pumpAndSettle();
      expect(themeMode, ThemeMode.dark);
    });

<<<<<<< yours
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
=======
    testWidgets('closing the sheet changes nothing', (tester) async {
      var calls = 0;
      await tester.pumpApp(view(onLocaleChanged: (_) => calls++));

      await tester.tap(find.byKey(const Key('settings_language')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings_choice_1')), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('settings_choice_1')), findsNothing);
      expect(calls, 0);
    });

    testWidgets('the sheet marks the current choice', (tester) async {
>>>>>>> kit a50ee3f
      await tester.pumpApp(
        view(settings: const AppSettings(themeMode: ThemeMode.light)),
      );
      await tester.tap(find.byKey(const Key('settings_theme')));
      await tester.pumpAndSettle();

      bool selected(int i) => tester
          .getSemantics(find.byKey(Key('settings_choice_$i')))
          .flagsCollection
          .isSelected
          .toBoolOrNull()!;
      expect(selected(1), isTrue);
      expect(selected(2), isFalse);
    });

    testWidgets('opens the privacy policy, terms and licenses', (tester) async {
      final opened = <String>[];
      await tester.pumpApp(
        view(
          onOpenPrivacy: () => opened.add('privacy'),
          onOpenTerms: () => opened.add('terms'),
          onOpenLicenses: () => opened.add('licenses'),
        ),
      );

<<<<<<< yours
      await tester.tap(find.byKey(const Key('settings_theme')));
      await tester.pumpAndSettle();
      final light = tester.widget<AppChoiceRow>(
        find.widgetWithText(AppChoiceRow, l10nEn.settingsThemeLight),
      );
      final dark = tester.widget<AppChoiceRow>(
        find.widgetWithText(AppChoiceRow, l10nEn.settingsThemeDark),
=======
      await tester.tap(find.text(l10nEn.settingsPrivacy));
      await tester.tap(find.text(l10nEn.settingsTerms));
      await tester.tap(find.text(l10nEn.settingsLicenses));
      expect(opened, ['privacy', 'terms', 'licenses']);
    });

    testWidgets('hides the About links without callbacks', (tester) async {
      await tester.pumpApp(view());
      expect(find.byKey(const Key('settings_privacy')), findsNothing);
      expect(find.byKey(const Key('settings_terms')), findsNothing);
      expect(find.byKey(const Key('settings_licenses')), findsNothing);
    });

    testWidgets('meets accessibility guidelines', (tester) async {
      await tester.pumpApp(
        view(onOpenPrivacy: () {}, onOpenTerms: () {}, onOpenLicenses: () {}),
>>>>>>> kit a50ee3f
      );
      await tester.pumpAndSettle();
      await tester.expectAccessible();
    });

    testWidgets('the choice sheet meets accessibility guidelines', (
      tester,
    ) async {
      await tester.pumpApp(view());
      await tester.tap(find.byKey(const Key('settings_language')));
      await tester.pumpAndSettle();
      await tester.expectAccessible();
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
