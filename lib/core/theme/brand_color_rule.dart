/// The gym brand colour rule (docs/designs/gym_brand_colours.md, "The colour
/// rule"): from one picked colour, the values the app uses in light and dark
/// mode, each with a guaranteed WCAG 2.2 contrast. Integers only after the
/// luminance table, so the dashboard's TypeScript copy gives the same bytes
/// (shared vectors: docs/features/brand_colour_vectors.json).
library;

import 'dart:math' as math;

/// One colour as red, green, blue (0–255).
typedef Rgb = (int r, int g, int b);

/// The values generated for one mode.
class BrandRule {
  const new({
    required this.brand,
    required this.onBrand,
    required this.primary,
    required this.onPrimary,
    required this.glowStart,
    required this.glowEnd,
    required this.adjusted,
  });

  /// Fills: buttons, progress, the workout pill, selected marks (≥ 3:1).
  final Rgb brand;

  /// Text and icons on [brand] (≥ 4.5:1).
  final Rgb onBrand;

  /// Coloured text, icons and borders on surfaces (≥ 4.5:1).
  final Rgb primary;

  /// Text on [primary] used as a fill (≥ 4.5:1).
  final Rgb onPrimary;

  /// The two tinted corners of the background, never stronger than Azm's.
  final Rgb glowStart;
  final Rgb glowEnd;

  /// How far [brand] moved from the picked colour, in percent (0 = as picked).
  final int adjusted;
}

abstract final class BrandColorRule {
  static const Rgb white = (255, 255, 255);
  static const Rgb black = (0, 0, 0);

  /// Azm's own green: its glow is the strongest a gym's glow may be.
  static const Rgb azm = (0x22, 0xC5, 0x5E);

  static const Rgb lightBackground = (0xEE, 0xF4, 0xF0);
  static const Rgb darkBackground = (0x07, 0x12, 0x0C);

  /// The surface each mode is checked against: the darker light surface and
  /// the lighter dark one, so passing here passes on the other one too.
  static const Rgb lightReference = lightBackground;
  static const Rgb darkReference = (0x14, 0x1E, 0x19);

  /// Channels this close together are black, white or a grey: not a brand.
  static const minSpread = 40;

  static final _hex = RegExp(r'^#[0-9a-f]{6}$');

  /// `#rrggbb` in lower case with enough colour, else null. Never throws.
  static Rgb? parse(Object? value) {
    if (value is! String || !_hex.hasMatch(value)) return null;
    final rgb = (
      int.parse(value.substring(1, 3), radix: 16),
      int.parse(value.substring(3, 5), radix: 16),
      int.parse(value.substring(5, 7), radix: 16),
    );
    return hasColour(rgb) ? rgb : null;
  }

  static bool hasColour(Rgb c) {
    final hi = math.max(c.$1, math.max(c.$2, c.$3));
    final lo = math.min(c.$1, math.min(c.$2, c.$3));
    return hi - lo >= minSpread;
  }

  static String hex(Rgb c) {
    String two(int v) => v.toRadixString(16).padLeft(2, '0');
    return '#${two(c.$1)}${two(c.$2)}${two(c.$3)}';
  }

  /// Linear value of each sRGB channel value × 1e6 (WCAG relative luminance).
  static final List<int> _linear = [for (var v = 0; v < 256; v++) _linearOf(v)];

  // Rounded to 1e-6, so a last-bit difference in `pow` between platforms
  // cannot change it; the shared vectors pin all 256 values.
  static int _linearOf(int v) {
    final s = v / 255;
    final lin = s <= 0.04045
        ? s / 12.92
        : math.pow((s + 0.055) / 1.055, 2.4).toDouble();
    return (lin * 1e6).round();
  }

  /// The table, for the shared vectors test.
  static List<int> get linearTable => List.unmodifiable(_linear);

  /// Relative luminance × 1e10.
  static int luminance(Rgb c) =>
      2126 * _linear[c.$1] + 7152 * _linear[c.$2] + 722 * _linear[c.$3];

  static const _flare = 500000000; // 0.05 × 1e10

  /// Whether the contrast of [a] and [b] is at least [num] : [den].
  static bool passes(Rgb a, Rgb b, int num, int den) {
    final x = luminance(a);
    final y = luminance(b);
    final hi = x > y ? x : y;
    final lo = x > y ? y : x;
    return den * (hi + _flare) >= num * (lo + _flare);
  }

  /// The contrast ratio, for showing (the checks use [passes]).
  static double ratio(Rgb a, Rgb b) {
    final x = luminance(a);
    final y = luminance(b);
    final hi = x > y ? x : y;
    final lo = x > y ? y : x;
    return (hi + _flare) / (lo + _flare);
  }

  /// [c] moved [k] percent of the way to [target].
  static Rgb mix(Rgb c, Rgb target, int k) => (
    (c.$1 * (100 - k) + target.$1 * k + 50) ~/ 100,
    (c.$2 * (100 - k) + target.$2 * k + 50) ~/ 100,
    (c.$3 * (100 - k) + target.$3 * k + 50) ~/ 100,
  );

  /// White when it reads on [fill] (≥ 4.5:1), else black (then always ≥ 4.5).
  static Rgb on(Rgb fill) => passes(white, fill, 9, 2) ? white : black;

  static (Rgb, int) _reach(Rgb c, Rgb toward, Rgb surface, int num, int den) {
    for (var k = 0; k <= 100; k++) {
      final v = mix(c, toward, k);
      if (passes(v, surface, num, den)) return (v, k);
    }
    return (toward, 100);
  }

  static Rgb _glow(Rgb fill, Rgb background, int from, {required bool dark}) {
    final limit = luminance(mix(azm, background, 55));
    for (var k = from; k <= 100; k++) {
      final g = mix(fill, background, k);
      final l = luminance(g);
      if (dark ? l <= limit : l >= limit) return g;
    }
    return background;
  }

  /// The values for [picked] in one mode.
  static BrandRule derive(Rgb picked, {required bool dark}) {
    final surface = dark ? darkReference : lightReference;
    final background = dark ? darkBackground : lightBackground;
    final toward = dark ? white : black;
    final (brand, adjusted) = _reach(picked, toward, surface, 3, 1);
    final (primary, _) = _reach(picked, toward, surface, 9, 2);
    return BrandRule(
      brand: brand,
      onBrand: on(brand),
      primary: primary,
      onPrimary: on(primary),
      glowStart: _glow(brand, background, 55, dark: dark),
      glowEnd: _glow(brand, background, 70, dark: dark),
      adjusted: adjusted,
    );
  }
}
