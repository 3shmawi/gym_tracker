import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_colors.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_fonts.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/theme/brand_colors.dart';

/// Light and dark themes built from [AppColors] and [AppTextStyles].
/// Must be read inside `ScreenUtilInit` (sizes are screen-scaled).
///
/// Themes are built once per (brightness, brand colour, screen scale) and
/// reused: a new `ThemeData` on every build would make every widget under
/// it rebuild.
abstract final class AppTheme {
  static ThemeData get light => of(Brightness.light);
  static ThemeData get dark => of(Brightness.dark);

  static final Map<(Brightness, int?, double), ThemeData> _cache = {};

  /// More than any session needs (two modes, a few gyms, a rotation).
  static const _maxCached = 16;

  /// Azm's theme, or with [gymColor] the theme of a gym that chose it.
  static ThemeData of(Brightness brightness, {Color? gymColor}) {
    final key = (brightness, gymColor?.toARGB32(), AppDimens.scale);
    final cached = _cache[key];
    if (cached != null) return cached;
    if (_cache.length >= _maxCached) _cache.clear();
    return _cache[key] = _build(
      brightness,
      gymColor == null
          ? BrandColors.azm(brightness)
          : BrandColors.fromSeed(gymColor, brightness),
    );
  }

  static ThemeData _build(Brightness brightness, BrandColors brand) {
    final isDark = brightness == Brightness.dark;
    final base = isDark ? AppPalette.dark : AppPalette.light;
    // Material's generated roles (card surfaces in lite mode, outlines,
    // containers) are always seeded from Azm's green: surfaces stay Azm's
    // for every gym, and they are what the brand's contrast is checked
    // against. Then pinned to the Design System tokens and the brand.
    final seeded = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    );
    final scheme = seeded.copyWith(
      primary: brand.primary,
      onPrimary: brand.onPrimary,
      surface: base.background,
      onSurface: base.textPrimary,
      onSurfaceVariant: base.textSecondary,
      error: base.error,
    );
    final palette = base.copyWith(
      brand: brand.brand,
      onBrand: brand.onBrand,
      brandDeep: brand.brandDeep,
      glowStart:
          brand.glowStart ?? Color.lerp(brand.brand, base.background, 0.55),
      glowEnd:
          brand.glowEnd ?? Color.lerp(seeded.tertiary, base.background, 0.7),
    );
    final radius = BorderRadius.circular(AppDimens.radiusMd);
    return ThemeData(
      colorScheme: scheme,
      extensions: [palette],
      fontFamily: AppFonts.latin,
      fontFamilyFallback: const [AppFonts.arabic],
      textTheme: TextTheme(
        displaySmall: AppTextStyles.display,
        headlineSmall: AppTextStyles.headline,
        titleLarge: AppTextStyles.title,
        titleMedium: AppTextStyles.title,
        bodyMedium: AppTextStyles.body,
        labelLarge: AppTextStyles.label,
        bodySmall: AppTextStyles.caption,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size.fromHeight(AppDimens.buttonHeight),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: AppTextStyles.label,
        ),
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        primaryColor: scheme.primary,
        brightness: brightness,
      ),
    );
  }
}
