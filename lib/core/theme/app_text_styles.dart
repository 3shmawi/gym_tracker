import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_fonts.dart';

/// Every text style in the app. Sizes use the clamped [AppDimens.scale].
/// Colors come from the theme, so these only define font, size, weight and
/// line height.
///
/// Each style names the font itself: a style passed straight to a widget
/// (e.g. a button's `textStyle`) does not inherit the theme's font, and
/// would fall back to the system font (SF / Roboto), without Cairo for
/// Arabic.
abstract final class AppTextStyles {
  static const _base = TextStyle(
    fontFamily: AppFonts.latin,
    fontFamilyFallback: [AppFonts.arabic],
  );

  static TextStyle get display => _base.copyWith(
    fontSize: AppDimens.scaled(32),
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
  static TextStyle get headline => _base.copyWith(
    fontSize: AppDimens.scaled(24),
    fontWeight: FontWeight.w700,
    height: 1.3,
  );
  static TextStyle get title => _base.copyWith(
    fontSize: AppDimens.scaled(18),
    fontWeight: FontWeight.w600,
    height: 1.3,
  );
  static TextStyle get body =>
      _base.copyWith(fontSize: AppDimens.scaled(14), height: 1.5);
  static TextStyle get label => _base.copyWith(
    fontSize: AppDimens.scaled(14),
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
  static TextStyle get caption =>
      _base.copyWith(fontSize: AppDimens.scaled(12), height: 1.4);
}
