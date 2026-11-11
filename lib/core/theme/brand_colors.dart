import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_colors.dart';
import 'package:gym_tracker/core/theme/brand_color_rule.dart';

/// The brand part of a theme: Azm's own green, or one gym's colour. The only
/// place the rest of the app's colours get their brand from (`AppTheme`).
@immutable
class BrandColors {
  const new({
    required this.brand,
    required this.onBrand,
    required this.brandDeep,
    required this.primary,
    required this.onPrimary,
    this.glowStart,
    this.glowEnd,
  });

  /// Azm's approved colours (docs/design.md). Not generated: the hand-tuned
  /// values, so nothing changes for anyone training without a gym colour.
  /// The glow is left to `AppTheme`, which keeps its original formula.
  factory azm(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return BrandColors(
      brand: AppColors.primary,
      onBrand: AppColors.onPrimary,
      brandDeep: AppColors.primaryDeep,
      // Light: the darker green carries text on white.
      primary: dark ? AppColors.primary : AppColors.primaryText,
      onPrimary: dark ? AppColors.onPrimary : Colors.white,
    );
  }

  /// A gym's colour, by the rule in docs/designs/gym_brand_colours.md: every
  /// value has its contrast guaranteed, whatever [seed] is.
  factory fromSeed(Color seed, Brightness brightness) {
    final rule = BrandColorRule.derive(
      toRgb(seed),
      dark: brightness == Brightness.dark,
    );
    return BrandColors(
      brand: toColor(rule.brand),
      onBrand: toColor(rule.onBrand),
      brandDeep: toColor(rule.brand),
      primary: toColor(rule.primary),
      onPrimary: toColor(rule.onPrimary),
      glowStart: toColor(rule.glowStart),
      glowEnd: toColor(rule.glowEnd),
    );
  }

  static Rgb toRgb(Color c) => (
    (c.r * 255).round().clamp(0, 255),
    (c.g * 255).round().clamp(0, 255),
    (c.b * 255).round().clamp(0, 255),
  );

  static Color toColor(Rgb c) => Color.fromARGB(255, c.$1, c.$2, c.$3);

  final Color brand;
  final Color onBrand;
  final Color brandDeep;
  final Color primary;
  final Color onPrimary;

  /// Null: `AppTheme` works the glow out from the seed, as it always has.
  final Color? glowStart;
  final Color? glowEnd;
}
