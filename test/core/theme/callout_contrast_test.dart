// Move games' big hints are read from the floor, 2 m away
// (docs/designs/plank_hold.md §6): their text must stand out on the fill.
import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/features/move/presentation/widgets/move_parts.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  for (final (name, palette) in [
    ('light', AppPalette.light),
    ('dark', AppPalette.dark),
  ]) {
    test('big hint text on its fill: at least 7:1 ($name)', () {
      expect(
        contrast(palette.onTrendDown, palette.trendDown),
        greaterThanOrEqualTo(HintChip.minContrast),
      );
    });
  }
}
