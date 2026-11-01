import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/theme/app_colors.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/ui/azm_logo_painter.dart';

import '../../helpers/pump_app.dart';

AzmLevelPainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(AzmLevelFigure),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as AzmLevelPainter;

void main() {
  testWidgets('60×70 box: height follows the width', (tester) async {
    await tester.pumpApp(
      const Center(
        child: AzmLevelFigure(figure: LevelFigure.beginner, width: 60),
      ),
    );
    expect(tester.getSize(find.byType(AzmLevelFigure)), const Size(60, 70));
    expect(AzmLevelFigure.heightFor(120), 140);
  });

  for (final (figure, en, ar) in const [
    (
      LevelFigure.beginner,
      'Beginner: a figure lifting a light bar',
      'مبتدئ: شخص بيرفع بار خفيف',
    ),
    (
      LevelFigure.intermediate,
      'Intermediate: a fitter figure with broader shoulders pressing a heavy '
          'bar',
      'متوسط: شخص أفرد بأكتاف أعرض بيرفع بار تقيل',
    ),
    (
      LevelFigure.pro,
      'Pro: a bodybuilder in a double-biceps pose',
      'محترف: لاعب كمال أجسام بيستعرض العضلتين',
    ),
  ]) {
    testWidgets('${figure.name}: one image with the design description', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpApp(
        Center(child: AzmLevelFigure(figure: figure, width: 60)),
      );
      expect(find.bySemanticsLabel(en), findsOneWidget);
      expect(find.byType(Text), findsNothing);
      await tester.pumpApp(
        Center(child: AzmLevelFigure(figure: figure, width: 60)),
        locale: const Locale('ar'),
      );
      expect(find.bySemanticsLabel(ar), findsOneWidget);
      handle.dispose();
    });
  }

  testWidgets('light background draws the lines dark', (tester) async {
    await tester.pumpApp(
      const Center(
        child: AzmLevelFigure(
          figure: LevelFigure.pro,
          width: 60,
          brightness: Brightness.light,
        ),
      ),
    );
    expect(_painter(tester).light, isTrue);
    expect(
      _painter(tester).shouldRepaint(const AzmLevelPainter(LevelFigure.pro)),
      isTrue,
    );
    expect(
      _painter(tester)
          .shouldRepaint(const AzmLevelPainter(LevelFigure.pro, light: true)),
      isFalse,
    );
  });

  testWidgets('not mirrored in Arabic (same paint, RTL or not)', (
    tester,
  ) async {
    await tester.pumpApp(
      const Center(child: AzmLevelFigure(figure: LevelFigure.pro, width: 60)),
      locale: const Locale('ar'),
    );
    expect(find.byType(Transform), findsNothing);
  });

  group('figures', () {
    for (final figure in LevelFigure.values) {
      for (final brightness in Brightness.values) {
        final name = '${figure.name}_${brightness.name}';
        testWidgets(name, tags: ['golden'], (tester) async {
          tester.view
            ..physicalSize = const Size(240, 280)
            ..devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: ColoredBox(
                color: brightness == Brightness.dark
                    ? AppColors.darkBg
                    : AppColors.lightBg,
                child: Center(
                  child: AzmLevelFigure(
                    figure: figure,
                    width: 80,
                    brightness: brightness,
                    semanticsLabel: name,
                  ),
                ),
              ),
            ),
          );
          await expectLater(
            find.byType(ColoredBox),
            matchesGoldenFile('goldens/azm_level/$name.png'),
          );
        });
      }
    }
  });
}
