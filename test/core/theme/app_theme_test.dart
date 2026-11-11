import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/theme/app_colors.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_theme.dart';
import 'package:gym_tracker/core/theme/brand_color_rule.dart';
import 'package:gym_tracker/core/theme/brand_colors.dart';

import '../../helpers/pump_app.dart';

void main() {
  testWidgets('Azm themes keep the approved values, exactly', (tester) async {
    await tester.pumpApp(const SizedBox());
    for (final brightness in Brightness.values) {
      final dark = brightness == Brightness.dark;
      final theme = AppTheme.of(brightness);
      final palette = theme.extension<AppPalette>()!;
      expect(palette.brand, AppColors.primary);
      expect(palette.onBrand, AppColors.onPrimary);
      expect(palette.brandDeep, AppColors.primaryDeep);
      expect(
        theme.colorScheme.primary,
        dark ? AppColors.primary : AppColors.primaryText,
      );
      expect(
        theme.colorScheme.onPrimary,
        dark ? AppColors.onPrimary : Colors.white,
      );
      // The background glow is the formula the app has always used.
      final seeded = ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: brightness,
      );
      expect(
        palette.glowStart,
        Color.lerp(AppColors.primary, palette.background, 0.55),
      );
      expect(
        palette.glowEnd,
        Color.lerp(seeded.tertiary, palette.background, 0.7),
      );
      // Never per gym.
      final base = dark ? AppPalette.dark : AppPalette.light;
      expect(palette.trendUp, base.trendUp);
      expect(palette.error, base.error);
    }
  });

  testWidgets('a gym colour changes the brand roles and nothing else', (
    tester,
  ) async {
    await tester.pumpApp(const SizedBox());
    const yellow = Color(0xFFFACC15);
    for (final brightness in Brightness.values) {
      final dark = brightness == Brightness.dark;
      final azm = AppTheme.of(brightness).extension<AppPalette>()!;
      final theme = AppTheme.of(brightness, gymColor: yellow);
      final palette = theme.extension<AppPalette>()!;
      final rule = BrandColorRule.derive((0xFA, 0xCC, 0x15), dark: dark);
      expect(palette.brand, BrandColors.toColor(rule.brand));
      expect(palette.onBrand, BrandColors.toColor(rule.onBrand));
      expect(palette.brandDeep, palette.brand);
      expect(theme.colorScheme.primary, BrandColors.toColor(rule.primary));
      expect(theme.colorScheme.onPrimary, BrandColors.toColor(rule.onPrimary));
      expect(palette.glowStart, BrandColors.toColor(rule.glowStart));
      for (final same in [
        (palette.background, azm.background),
        (palette.surfaceSolid, azm.surfaceSolid),
        (palette.textPrimary, azm.textPrimary),
        (palette.textSecondary, azm.textSecondary),
        (palette.trendUp, azm.trendUp),
        (palette.trendKeep, azm.trendKeep),
        (palette.trendDown, azm.trendDown),
        (palette.trendNew, azm.trendNew),
        (palette.error, azm.error),
      ]) {
        expect(same.$1, same.$2);
      }
      expect(theme.colorScheme.error, azm.error);
      // Card surfaces and outlines do not take the gym's hue.
      final azmScheme = AppTheme.of(brightness).colorScheme;
      expect(
        theme.colorScheme.surfaceContainerHigh,
        azmScheme.surfaceContainerHigh,
      );
      expect(theme.colorScheme.outline, azmScheme.outline);
      expect(theme.colorScheme.secondary, azmScheme.secondary);
    }
  });

  testWidgets('themes are built once and reused', (tester) async {
    await tester.pumpApp(const SizedBox());
    expect(identical(AppTheme.light, AppTheme.light), isTrue);
    expect(identical(AppTheme.dark, AppTheme.of(Brightness.dark)), isTrue);
    const navy = Color(0xFF1E3A8A);
    expect(
      identical(
        AppTheme.of(Brightness.dark, gymColor: navy),
        AppTheme.of(Brightness.dark, gymColor: navy),
      ),
      isTrue,
    );
    expect(
      identical(AppTheme.dark, AppTheme.of(Brightness.dark, gymColor: navy)),
      isFalse,
    );
  });

  test('the palette blends its brand roles between two themes', () {
    const a = AppPalette.dark;
    final b = a.copyWith(
      brand: const Color(0xFF000000),
      onBrand: const Color(0xFFFFFFFF),
    );
    final mid = a.lerp(b, 0.5);
    expect(mid.brand, Color.lerp(a.brand, b.brand, 0.5));
    expect(mid.onBrand, Color.lerp(a.onBrand, b.onBrand, 0.5));
    expect(a.lerp(b, 1).brand, b.brand);
    expect(a.brandTint, a.brand.withValues(alpha: 0.2));
  });
}
