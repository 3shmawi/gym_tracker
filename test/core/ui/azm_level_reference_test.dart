import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/theme/app_colors.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';

/// The Flutter port must match the approved level figures: the frames in
/// level_reference/ are rendered by Chromium straight from
/// docs/design/motion/level_figures.dc.html (scripts/level_reference.js).
///
/// Anti-aliasing differs a little between the two renderers, so only clear
/// differences count (the same thresholds as the logo's reference test).
const _channelTolerance = 24;
const _maxDifferent = .012;

void main() {
  for (final (symbol, figure) in const [
    ('lv1', LevelFigure.beginner),
    ('lv2', LevelFigure.intermediate),
    ('lv3', LevelFigure.pro),
  ]) {
    testWidgets('$symbol matches the design', (tester) async {
      tester.view
        ..physicalSize = const Size(240, 280)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: AppColors.darkBg,
            child: Center(
              child: AzmLevelFigure(
                figure: figure,
                width: 80,
                semanticsLabel: symbol,
              ),
            ),
          ),
        ),
      );
      final diff = await tester.runAsync(() async {
        final actual = await captureImage(
          find.byType(ColoredBox).evaluate().single,
        );
        final expected = await _decode(
          File('test/core/ui/level_reference/$symbol.png'),
        );
        return _differentFraction(await _rgba(actual), await _rgba(expected));
      });
      expect(diff, lessThan(_maxDifferent), reason: symbol);
    });
  }
}

Future<ui.Image> _decode(File file) async {
  final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

Future<Uint8List> _rgba(ui.Image image) async {
  expect(image.width, 240);
  expect(image.height, 280);
  final data = await image.toByteData();
  return data!.buffer.asUint8List();
}

double _differentFraction(Uint8List a, Uint8List b) {
  var different = 0;
  for (var i = 0; i < a.length; i += 4) {
    for (var c = 0; c < 3; c++) {
      if ((a[i + c] - b[i + c]).abs() > _channelTolerance) {
        different++;
        break;
      }
    }
  }
  return different / (a.length / 4);
}
