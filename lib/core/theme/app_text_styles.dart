import 'dart:math' as math;

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

  /// Screen-scaled size, except small text (≤ 14) never shrinks below its
  /// design size: 12 × 0.9 on a small phone would be unreadable.
  static double _size(double design) => design <= 14
      ? math.max(design, AppDimens.scaled(design))
      : AppDimens.scaled(design);

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
  static TextStyle get body => _base.copyWith(fontSize: _size(14), height: 1.5);
  static TextStyle get label => _base.copyWith(
    fontSize: _size(14),
    fontWeight: FontWeight.w600,
    height: 1.2,
  );
  static TextStyle get caption =>
      _base.copyWith(fontSize: _size(12), height: 1.4);

  // Numbers (weight, reps, timer): Inter with tabular figures so digits
  // don't jump while they change. Wrap them in an LTR Directionality inside
  // Arabic text so "22.5 × 12" never reorders.
  static const _numbers = TextStyle(
    fontFamily: AppFonts.latin,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
    height: 1,
  );

  /// Rest timer countdown.
  static TextStyle get numHero =>
      _numbers.copyWith(fontSize: AppDimens.scaled(64), letterSpacing: -1.5);

  /// Stepper value (weight, reps).
  static TextStyle get numXL =>
      _numbers.copyWith(fontSize: AppDimens.scaled(40), letterSpacing: -0.8);

  /// Summary figures.
  static TextStyle get numL =>
      _numbers.copyWith(fontSize: AppDimens.scaled(22));

  /// Suggested weight in lists.
  static TextStyle get numM =>
      _numbers.copyWith(fontSize: AppDimens.scaled(17), height: 1.2);
}
