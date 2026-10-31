import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_colors.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_fonts.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';

/// Light and dark themes built from [AppColors] and [AppTextStyles].
/// Must be read inside `ScreenUtilInit` (sizes are screen-scaled).
abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    );
    final radius = BorderRadius.circular(AppDimens.radiusMd);
    return ThemeData(
      colorScheme: scheme,
      fontFamily: AppFonts.latin,
      fontFamilyFallback: const [AppFonts.arabic],
      textTheme: TextTheme(
        displaySmall: AppTextStyles.display,
        headlineSmall: AppTextStyles.headline,
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
