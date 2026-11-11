import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_colors.dart';

/// Theme-dependent Design System colors that ColorScheme has no slot for:
/// trends, subtle fills, the solid "lite" surface. Read with
/// `context.palette`.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const new({
    required this.background,
    required this.glow1,
    required this.glow2,
    required this.surfaceSolid,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.fillSubtle,
    required this.keyFill,
    required this.trendUp,
    required this.trendKeep,
    required this.trendDown,
    required this.trendNew,
    required this.error,
    required this.brand,
    required this.onBrand,
    required this.brandDeep,
    required this.glowStart,
    required this.glowEnd,
  });

  static const dark = AppPalette(
    background: AppColors.darkBg,
    glow1: AppColors.darkGlow1,
    glow2: AppColors.darkGlow2,
    surfaceSolid: AppColors.darkSurface,
    textPrimary: AppColors.darkText1,
    textSecondary: AppColors.darkText2,
    textTertiary: AppColors.darkText3,
    fillSubtle: Color(0x12FFFFFF), // white 7%
    keyFill: Color(0x24FFFFFF), // white 14%: keys stand out from the track
    trendUp: AppColors.darkUp,
    trendKeep: AppColors.darkKeep,
    trendDown: AppColors.darkDown,
    trendNew: AppColors.darkNew,
    error: AppColors.darkError,
    brand: AppColors.primary,
    onBrand: AppColors.onPrimary,
    brandDeep: AppColors.primaryDeep,
    glowStart: AppColors.darkGlow1,
    glowEnd: AppColors.darkGlow2,
  );

  static const light = AppPalette(
    background: AppColors.lightBg,
    glow1: AppColors.lightGlow1,
    glow2: AppColors.lightGlow2,
    surfaceSolid: AppColors.lightSurface,
    textPrimary: AppColors.lightText1,
    textSecondary: AppColors.lightText2,
    textTertiary: AppColors.lightText3,
    fillSubtle: Color(0x0F0C1610), // ink 6%
    keyFill: AppColors.lightSurface,
    trendUp: AppColors.lightUp,
    trendKeep: AppColors.lightKeep,
    trendDown: AppColors.lightDown,
    trendNew: AppColors.lightNew,
    error: AppColors.lightError,
    brand: AppColors.primary,
    onBrand: AppColors.onPrimary,
    brandDeep: AppColors.primaryDeep,
    glowStart: AppColors.lightGlow1,
    glowEnd: AppColors.lightGlow2,
  );

  final Color background;
  final Color glow1;
  final Color glow2;
  final Color surfaceSolid;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color fillSubtle;

  /// Stepper keys and other raised controls on a [fillSubtle] track.
  final Color keyFill;
  final Color trendUp;
  final Color trendKeep;
  final Color trendDown;
  final Color trendNew;
  final Color error;

  /// The brand fill: buttons, progress, the workout pill, selected marks.
  /// Azm's green, or the active gym's colour (`BrandColors`).
  final Color brand;

  /// Text and icons on [brand].
  final Color onBrand;

  /// The far end of a [brand] gradient that [onBrand] still reads on. A gym
  /// colour has none: it is [brand] itself, so the contrast stays guaranteed.
  final Color brandDeep;

  /// The two tinted corners of `AppBackground`. `AppTheme` sets them; the
  /// constants here only stand in when no theme is installed.
  final Color glowStart;
  final Color glowEnd;

  /// A soft [brand] fill behind content (done sets, a selected choice).
  Color get brandTint => brand.withValues(alpha: 0.2);

  @override
  AppPalette copyWith({
    Color? background,
    Color? brand,
    Color? onBrand,
    Color? brandDeep,
    Color? glowStart,
    Color? glowEnd,
  }) => AppPalette(
    background: background ?? this.background,
    glow1: glow1,
    glow2: glow2,
    surfaceSolid: surfaceSolid,
    textPrimary: textPrimary,
    textSecondary: textSecondary,
    textTertiary: textTertiary,
    fillSubtle: fillSubtle,
    keyFill: keyFill,
    trendUp: trendUp,
    trendKeep: trendKeep,
    trendDown: trendDown,
    trendNew: trendNew,
    error: error,
    brand: brand ?? this.brand,
    onBrand: onBrand ?? this.onBrand,
    brandDeep: brandDeep ?? this.brandDeep,
    glowStart: glowStart ?? this.glowStart,
    glowEnd: glowEnd ?? this.glowEnd,
  );

  @override
  AppPalette lerp(AppPalette? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppPalette(
      background: l(background, other.background),
      glow1: l(glow1, other.glow1),
      glow2: l(glow2, other.glow2),
      surfaceSolid: l(surfaceSolid, other.surfaceSolid),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      fillSubtle: l(fillSubtle, other.fillSubtle),
      keyFill: l(keyFill, other.keyFill),
      trendUp: l(trendUp, other.trendUp),
      trendKeep: l(trendKeep, other.trendKeep),
      trendDown: l(trendDown, other.trendDown),
      trendNew: l(trendNew, other.trendNew),
      error: l(error, other.error),
      brand: l(brand, other.brand),
      onBrand: l(onBrand, other.onBrand),
      brandDeep: l(brandDeep, other.brandDeep),
      glowStart: l(glowStart, other.glowStart),
      glowEnd: l(glowEnd, other.glowEnd),
    );
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}
