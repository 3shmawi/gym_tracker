import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The brand colour reaches widgets only through the theme
/// (`context.palette.brand`, `colorScheme.primary`), so a gym's colour
/// changes every screen at once. A direct use of the green outside
/// `lib/core/theme/` would stay green inside a gym.
void main() {
  test('no file outside lib/core/theme uses the brand green directly', () {
    final forbidden = RegExp(
      r'AppColors\.(primary|primaryText|primaryDeep|onPrimary)\b'
      '|22C55E|15803D|04210F|0B6B33',
      caseSensitive: false,
    );
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final path = file.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/core/theme/')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (forbidden.hasMatch(lines[i])) offenders.add('$path:${i + 1}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'Read the brand colour from the theme (context.palette.brand / '
          'onBrand / brandTint, or colorScheme.primary). A fixed Azm colour '
          'gets a named constant in lib/core/theme/app_colors.dart.',
    );
  });

  test('the check catches a direct use', () {
    final forbidden = RegExp(r'AppColors\.(primary|onPrimary)\b');
    expect(forbidden.hasMatch('color: AppColors.primary,'), isTrue);
    expect(forbidden.hasMatch('color: AppColors.primaryish,'), isFalse);
  });
}
