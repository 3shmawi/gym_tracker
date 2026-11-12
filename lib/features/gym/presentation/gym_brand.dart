import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/feature_flags/feature_flags.dart';
import 'package:gym_tracker/core/theme/app_theme.dart';
import 'package:gym_tracker/core/theme/brand_color_rule.dart';
import 'package:gym_tracker/core/theme/brand_colors.dart';
import 'package:gym_tracker/features/gym/presentation/gym_providers.dart';

/// Whether gyms may colour the app (`Flags.gymBrandColours`). Starts from
/// the answer kept on the phone, so the app opens in the right colours, then
/// asks PostHog once and remembers what it said.
final gymBrandColoursEnabledProvider =
    NotifierProvider<GymBrandColoursFlag, bool>(GymBrandColoursFlag.new);

class GymBrandColoursFlag extends Notifier<bool> {
  @override
  bool build() {
    unawaited(_refresh());
    return Dependencies.flagCache.read(Flags.gymBrandColours) ?? false;
  }

  Future<void> _refresh() async {
    final bool enabled;
    try {
      enabled = await FeatureFlags.isEnabled(Flags.gymBrandColours);
    } on Object {
      return; // Keep the last known answer.
    }
    if (!ref.mounted) return;
    await Dependencies.flagCache.write(Flags.gymBrandColours, value: enabled);
    if (ref.mounted && state != enabled) state = enabled;
  }
}

/// The colour of the gym the person is training in now, or null for Azm's
/// colours: training solo, a membership that ended, a gym with no colour, a
/// value the app does not accept, or the flag off. Changes only when the
/// colour does.
final activeBrandColorProvider = Provider<Color?>((ref) {
  if (!ref.watch(gymBrandColoursEnabledProvider)) return null;
  final hex = ref.watch(
    gymControllerProvider.select((s) {
      final m = s.value?.activeMembership;
      return m != null && m.isActive ? m.gym.brandColor : null;
    }),
  );
  final rgb = BrandColorRule.parse(hex);
  return rgb == null ? null : BrandColors.toColor(rgb);
});

/// Puts the active gym's colour on everything below it (the navigator: every
/// screen, sheet and dialog). Above it (the update gate, the consent gate)
/// stays Azm's. With no gym colour it hands down the app's own theme
/// object, so nothing rebuilds.
class BrandThemeHost extends ConsumerWidget {
  const new({required this.child, super.key});

  final Widget child;

  static const duration = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = ref.watch(activeBrandColorProvider);
    final brightness = Theme.of(context).brightness;
    ref.listen(activeBrandColorProvider, (previous, next) {
      if (next == null || next == previous) return;
      final rule = BrandColorRule.derive(
        BrandColors.toRgb(next),
        dark: brightness == Brightness.dark,
      );
      unawaited(
        Analytics.capture('gym_theme_applied', {
          'mode': brightness == Brightness.dark ? 'dark' : 'light',
          'adjusted': rule.adjusted > 0,
        }),
      );
    });
    return AnimatedTheme(
      data: AppTheme.of(brightness, gymColor: color),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : duration,
      child: child,
    );
  }
}
