import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/theme/brand_color_rule.dart';

/// The rule against the vectors the dashboard's TypeScript copy and pgTAP
/// also read (docs/features/brand_colour_vectors.json), then its guarantees
/// on a sweep of the colour cube.
void main() {
  final vectors = jsonDecode(
    File('docs/features/brand_colour_vectors.json').readAsStringSync(),
  ) as Map<String, Object?>;

  test('the luminance table is the shared one, all 256 values', () {
    expect(BrandColorRule.linearTable, vectors['linear']);
  });

  test('every shared colour gives the shared values in both modes', () {
    final colours = (vectors['colours']! as List<Object?>)
        .cast<Map<String, Object?>>();
    expect(colours.length, greaterThanOrEqualTo(60));
    for (final c in colours) {
      final picked = BrandColorRule.parse(c['picked'])!;
      for (final dark in [false, true]) {
        final want = c[dark ? 'dark' : 'light']! as Map<String, Object?>;
        final got = BrandColorRule.derive(picked, dark: dark);
        expect(
          {
            'brand': BrandColorRule.hex(got.brand),
            'onBrand': BrandColorRule.hex(got.onBrand),
            'primary': BrandColorRule.hex(got.primary),
            'onPrimary': BrandColorRule.hex(got.onPrimary),
            'glowStart': BrandColorRule.hex(got.glowStart),
            'glowEnd': BrandColorRule.hex(got.glowEnd),
            'adjusted': got.adjusted,
          },
          want,
          reason: '${c['picked']} ${dark ? 'dark' : 'light'}',
        );
      }
    }
  });

  test('valid codes parse; anything else is null and never throws', () {
    for (final v in vectors['valid']! as List<Object?>) {
      expect(BrandColorRule.parse(v), isNotNull, reason: '$v');
    }
    final hostile = [
      ...vectors['invalid']! as List<Object?>,
      null,
      42,
      4.2,
      true,
      <String>['#facc15'],
      {'hex': '#facc15'},
      '#facc15' * 100000,
      '\u0000#facc15',
      '#FACC15',
      '<script>alert(1)</script>',
    ];
    for (final v in hostile) {
      expect(BrandColorRule.parse(v), isNull, reason: '$v'.take(40));
    }
  });

  test('a colour and the code it prints are the same thing', () {
    expect(BrandColorRule.hex(BrandColorRule.parse('#0a0bfc')!), '#0a0bfc');
  });

  test(
    'guarantees on a sweep of the cube: fills 3:1, text 4.5:1, readable tint',
    () {
      for (final dark in [false, true]) {
        final surface = dark
            ? BrandColorRule.darkReference
            : BrandColorRule.lightReference;
        final background = dark
            ? BrandColorRule.darkBackground
            : BrandColorRule.lightBackground;
        final text = dark ? (0xF2, 0xF7, 0xF3) : (0x0C, 0x16, 0x10);
        final glowLimit = BrandColorRule.luminance(
          BrandColorRule.mix(BrandColorRule.azm, background, 55),
        );
        for (var r = 0; r < 256; r += 15) {
          for (var g = 0; g < 256; g += 15) {
            for (var b = 0; b < 256; b += 15) {
              final rule = BrandColorRule.derive((r, g, b), dark: dark);
              final why = '($r,$g,$b) dark=$dark';
              expect(
                BrandColorRule.passes(rule.brand, surface, 3, 1),
                isTrue,
                reason: 'brand $why',
              );
              expect(
                BrandColorRule.passes(rule.onBrand, rule.brand, 9, 2),
                isTrue,
                reason: 'onBrand $why',
              );
              expect(
                BrandColorRule.passes(rule.primary, surface, 9, 2),
                isTrue,
                reason: 'primary $why',
              );
              expect(
                BrandColorRule.passes(rule.onPrimary, rule.primary, 9, 2),
                isTrue,
                reason: 'onPrimary $why',
              );
              // Main text on the 20% tint used behind done sets.
              final tint = BrandColorRule.mix(rule.brand, surface, 80);
              expect(
                BrandColorRule.passes(text, tint, 9, 2),
                isTrue,
                reason: 'tint $why',
              );
              // The glow is never stronger than Azm's own.
              for (final glow in [rule.glowStart, rule.glowEnd]) {
                final l = BrandColorRule.luminance(glow);
                expect(
                  dark ? l <= glowLimit : l >= glowLimit,
                  isTrue,
                  reason: 'glow $why',
                );
              }
            }
          }
        }
      }
    },
  );

  test('a colour that already passes is used as picked', () {
    final navy = BrandColorRule.derive((0x1E, 0x3A, 0x8A), dark: false);
    expect(navy.adjusted, 0);
    expect(BrandColorRule.hex(navy.brand), '#1e3a8a');
    final yellow = BrandColorRule.derive((0xFA, 0xCC, 0x15), dark: true);
    expect(yellow.adjusted, 0);
  });
}

extension on String {
  String take(int n) => length <= n ? this : substring(0, n);
}
