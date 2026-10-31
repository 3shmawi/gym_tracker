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

  @override
  AppPalette copyWith({Color? background}) => AppPalette(
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
    );
  }
}

extension AppPaletteContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;
}
