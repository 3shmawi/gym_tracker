import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/theme/app_colors.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/ui/azm_logo_painter.dart';

/// The Flutter port must match the approved design frame by frame: the
/// frames in motion_reference/ are rendered by Chromium straight from
/// docs/design/motion/splash_animation.dc.html (scripts/motion_reference.js).
///
/// Anti-aliasing differs a little between the two renderers, so only clear
/// differences count: a shape moved, resized or recoloured by even ~1 unit
/// makes far more than [_maxDifferent] of the pixels differ.
const List<num> _frames = [0, .18, .3, .48, .5, .6, .66, .75, .79, .9, .93, 1];
const _channelTolerance = 24;
const _maxDifferent = .012;

void main() {
  for (final t in _frames) {
    testWidgets('frame $t matches the design', (tester) async {
      tester.view
        ..physicalSize = const Size(336, 336)
        ..devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ColoredBox(
            color: AppColors.darkBg,
            child: Center(
              child: AzmLogoAnimation(
                size: AzmLogoPainter.viewUnits,
                progress: t.toDouble(),
                semanticsLabel: 'Loading',
              ),
            ),
          ),
        ),
      );

      final name = t == 0 || t == 1 ? '${t.toInt()}' : '$t';
      final diff = await tester.runAsync(() async {
        final actual = await captureImage(
          find.byType(ColoredBox).evaluate().single,
        );
        final expected = await _decode(
          File('test/core/ui/motion_reference/frame_$name.png'),
        );
        return _differentFraction(await _rgba(actual), await _rgba(expected));
      });
      expect(diff, lessThan(_maxDifferent), reason: 'frame $t');
    });
  }
}

Future<ui.Image> _decode(File file) async {
  final codec = await ui.instantiateImageCodec(file.readAsBytesSync());
  return (await codec.getNextFrame()).image;
}

Future<Uint8List> _rgba(ui.Image image) async {
  expect(image.width, 336);
  expect(image.height, 336);
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
