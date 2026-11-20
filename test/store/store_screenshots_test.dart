import 'dart:convert';

import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_theme.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/l10n/l10n.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

import 'store_screens.dart';

/// Renders [storeScreens] for the store images (store/README.md →
/// Screenshots), in Arabic and English, dark mode, with the app's fonts:
///
///   flutter test test/store/store_screenshots_test.dart \
///     --update-goldens --dart-define=STORE_SHOTS=true
///
/// Writes `store/tools/raw/<screen>__store<phone|tablet>_<ar|en>_dark.png`.
/// Skipped in normal test runs.
void main() {
  const enabled = bool.fromEnvironment('STORE_SHOTS');
  // Logical sizes ×3: the phone is iPhone 6.9" (1320×2868), the tablet an
  // iPad portrait.
  const devices = {'phone': Size(440, 956), 'tablet': Size(820, 1180)};

  setUpAll(() async {
    if (enabled) await _loadFonts();
  });

  for (final MapEntry(key: name, value: build) in storeScreens.entries) {
    for (final MapEntry(key: device, value: size) in devices.entries) {
      for (final locale in const ['ar', 'en']) {
        testWidgets('$name · $device · $locale', (tester) async {
          tester.view
            ..physicalSize = size * 3
            ..devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            AppUi.testWrap(
              ScreenUtilInit(
                designSize: AppDimens.designSize,
                builder: (context, _) => MaterialApp(
                  debugShowCheckedModeBanner: false,
                  locale: Locale(locale),
                  theme: AppTheme.light,
                  darkTheme: AppTheme.dark,
                  themeMode: ThemeMode.dark,
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: build(),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await _precacheImages(tester);
          await expectLater(
            find.byType(MaterialApp),
            matchesGoldenFile(
              '../../store/tools/raw/${name}__store${device}_${locale}_dark.png',
            ),
          );
        }, skip: !enabled);
      }
    }
  }
}

/// Real glyphs instead of the test font: every font in the app's font
/// manifest (the app's fonts, Material and Cupertino icons).
Future<void> _loadFonts() async {
  final manifest = jsonDecode(
    await rootBundle.loadString('FontManifest.json'),
  ) as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font
        in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
}

/// Pictures decode asynchronously; without this a screenshot shows an empty
/// box where an image goes.
Future<void> _precacheImages(WidgetTester tester) async {
  final images = tester.elementList(find.byType(Image)).toList();
  if (images.isEmpty) return;
  await tester.runAsync(() async {
    for (final element in images) {
      await precacheImage((element.widget as Image).image, element);
    }
  });
  await tester.pumpAndSettle();
}
