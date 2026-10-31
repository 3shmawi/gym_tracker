import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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
        ScreenUtilInit(
          designSize: AppDimens.designSize,
          builder: (context, _) => MaterialApp(
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
  Future<void> expectAccessible() async {
    final handle = ensureSemantics();
    await pumpAndSettle();
    await expectLater(this, meetsGuideline(androidTapTargetGuideline));
    await expectLater(this, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(this, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(this, meetsGuideline(textContrastGuideline));
    handle.dispose();
  }
}

/// English strings, for finders: `find.text(l10nEn.settingsTitle)`.
final AppLocalizations l10nEn = lookupAppLocalizations(const Locale('en'));
