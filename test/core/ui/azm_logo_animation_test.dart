import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/theme/app_colors.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/ui/azm_logo_painter.dart';

import '../../helpers/pump_app.dart';

/// The moments in docs/design/motion/README.md, as fractions of 2.6 s.
const keyFrames = <String, double>{
  'light_lift': .18,
  'heavy_lift': .48,
  'flex': .79,
  'end_logo': 1,
};

Widget _frame(double progress) => Directionality(
  textDirection: TextDirection.ltr,
  child: ColoredBox(
    color: AppColors.darkBg,
    child: Center(
      child: AzmLogoAnimation(
        size: AzmLogoPainter.viewUnits,
        progress: progress,
        semanticsLabel: 'Loading',
      ),
    ),
  ),
);

AzmLogoPainter _painter(WidgetTester tester) =>
    tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(AzmLogoAnimation),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter!
        as AzmLogoPainter;

void main() {
  testWidgets('plays once and ends on the static logo', (tester) async {
    var completed = 0;
    await tester.pumpApp(
      Center(
        child: AzmLogoAnimation(size: 166, onCompleted: () => completed++),
      ),
    );
    expect(_painter(tester).progress, 0);

    await tester.pump(const Duration(milliseconds: 1300));
    expect(_painter(tester).progress, closeTo(.5, .01));
    expect(completed, 0);

    await tester.pumpAndSettle();
    expect(_painter(tester).progress, 1);
    expect(completed, 1);
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('loops when asked', (tester) async {
    var completed = 0;
    await tester.pumpApp(
      Center(
        child: AzmLogoAnimation(
          size: 64,
          loop: true,
          onCompleted: () => completed++,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 2600 + 650));
    expect(_painter(tester).progress, closeTo(.25, .01));
    await tester.pump(const Duration(milliseconds: 2600));
    expect(_painter(tester).progress, closeTo(.25, .01));
    expect(tester.hasRunningAnimations, isTrue);
    expect(completed, 0);
  });

  testWidgets('custom duration', (tester) async {
    await tester.pumpApp(
      const Center(
        child: AzmLogoAnimation(size: 64, duration: Duration(seconds: 1)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(_painter(tester).progress, closeTo(.5, .01));
  });

  testWidgets('Reduce Motion shows the static logo, no motion', (tester) async {
    var completed = 0;
    await tester.pumpApp(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Center(
          child: AzmLogoAnimation(
            size: 166,
            loop: true,
            onCompleted: () => completed++,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(_painter(tester).progress, 1);
    expect(tester.hasRunningAnimations, isFalse);
    expect(completed, 1);
  });

  testWidgets('one semantics label, no text', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpApp(const Center(child: AzmLogoAnimation(size: 166)));
    expect(find.byType(Text), findsNothing);
    expect(find.byType(RichText), findsNothing);
    final node = tester.getSemantics(find.byType(AzmLogoAnimation));
    expect(node.label, l10nEn.loading);
    var children = 0;
    node.visitChildren((_) {
      children++;
      return true;
    });
    expect(children, 0);
    expect(find.bySemanticsLabel(l10nEn.loading), findsOneWidget);
    await tester.pumpAndSettle();
    handle.dispose();
  });

  testWidgets('the label follows the app language', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpApp(
      const Center(child: AzmLogoAnimation(size: 166)),
      locale: const Locale('ar'),
    );
    expect(find.bySemanticsLabel('جاري التحميل'), findsOneWidget);
    await tester.pumpAndSettle();
    handle.dispose();
  });

  testWidgets('works before the app has localizations (splash)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: AzmLogoAnimation(size: 166)),
      ),
    );
    await tester.pumpAndSettle();
    expect(_painter(tester).progress, 1);
  });

  testWidgets('every frame paints without errors', (tester) async {
    for (var i = 0; i <= 100; i++) {
      await tester.pumpWidget(_frame(i / 100));
    }
    expect(tester.takeException(), isNull);
  });

  group('key frames', () {
    for (final MapEntry(key: name, value: t) in keyFrames.entries) {
      testWidgets(name, tags: ['golden'], (tester) async {
        tester.view
          ..physicalSize = const Size(336, 336)
          ..devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_frame(t));
        await expectLater(
          find.byType(ColoredBox),
          matchesGoldenFile('goldens/azm_logo/$name.png'),
        );
      });
    }
  });
}
