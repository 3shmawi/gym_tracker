import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_theme.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/l10n/l10n.dart';

extension PumpApp on WidgetTester {
  /// Pumps [widget] inside everything a screen expects: ScreenUtil, theme
  /// and localizations.
  /// The screen is a 375×812 phone (the design frame), so screen-scaled
  /// sizes in tests match real devices.
  Future<void> pumpApp(Widget widget, {Locale locale = const Locale('en')}) {
    view
      ..physicalSize = const Size(1125, 2436)
      ..devicePixelRatio = 3;
    addTearDown(view.reset);
    return pumpWidget(
      AppUi.testWrap(
        AppScreenScale(
          builder: (context) => MaterialApp(
            locale: locale,
            theme: AppTheme.light,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: widget,
          ),
        ),
      ),
    );
  }
}

extension AccessibilityChecks on WidgetTester {
  /// Fails when the current screen breaks Android/iOS tap-target sizes,
  /// leaves a tappable element without a label, or has low text contrast.
  /// Call it in every screen's widget test (CLAUDE.md → UI rules).
  ///
  /// [checkContrast] is off only for Arabic: the test font has no Arabic
  /// glyphs (it draws hollow boxes), so the contrast check would sample the
  /// background. Arabic uses the same colors, checked on the English run.
  Future<void> expectAccessible({bool checkContrast = true}) async {
    final handle = ensureSemantics();
    await pumpAndSettle();
    await expectLater(this, meetsGuideline(androidTapTargetGuideline));
    await expectLater(this, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(this, meetsGuideline(labeledTapTargetGuideline));
    if (checkContrast) {
      await expectLater(this, meetsGuideline(textContrastGuideline));
    }
    handle.dispose();
  }
}

/// English strings, for finders: `find.text(l10nEn.settingsTitle)`.
final AppLocalizations l10nEn = lookupAppLocalizations(const Locale('en'));
