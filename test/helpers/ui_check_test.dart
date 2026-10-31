import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../flutter_test_config.dart';
import 'ui_check.dart';

/// The UI checks must catch the bugs they exist for. Each case pumps a
/// deliberately broken screen and expects the check to fail.
void main() {
  const small = UiVariant(device: 'small');
  const tablet = UiVariant(device: 'tablet');

  setUpAll(() async {
    await loadAppFonts();
  });

  Future<void> pump(WidgetTester tester, Widget body, UiVariant v) =>
      tester.pumpVariant(Scaffold(body: SafeArea(child: body)), v);

  testWidgets('passes a well-proportioned screen', (tester) async {
    await pump(tester, const Center(child: Text('Wide Lat Pulldown')), small);
    tester
      ..expectSaneLayout(small)
      ..expectNotZoomed(small);
  });

  testWidgets('catches a row wider than the screen (overflow)', (tester) async {
    await pump(
      tester,
      const Row(
        children: [
          SizedBox(width: 200, height: 56),
          SizedBox(width: 200, height: 56),
        ],
      ),
      small,
    );
    expect(tester.takeException(), isA<FlutterError>());
  });

  testWidgets('catches a box sticking out of the screen', (tester) async {
    await pump(
      tester,
      const OverflowBox(maxWidth: 500, child: SizedBox(width: 500, height: 40)),
      small,
    );
    expect(() => tester.expectSaneLayout(small), throwsA(isA<TestFailure>()));
  });

  testWidgets('catches text that is too small to read', (tester) async {
    await pump(
      tester,
      const Text('22.5 × 12', style: TextStyle(fontSize: 9)),
      small,
    );
    expect(() => tester.expectSaneLayout(small), throwsA(isA<TestFailure>()));
  });

  testWidgets('catches text in a non-app font', (tester) async {
    await pump(
      tester,
      const Text('Log set', style: TextStyle(fontFamily: 'Roboto')),
      small,
    );
    expect(() => tester.expectSaneLayout(small), throwsA(isA<TestFailure>()));
  });

  testWidgets('catches cut-off text', (tester) async {
    await pump(
      tester,
      const SizedBox(
        width: 60,
        child: Text(
          'Straight-Arm Cable Pulldown',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      small,
    );
    expect(() => tester.expectSaneLayout(small), throwsA(isA<TestFailure>()));
  });

  testWidgets('catches zoomed text on a tablet', (tester) async {
    await pump(
      tester,
      const Text('Start', style: TextStyle(fontSize: 48)),
      tablet,
    );
    expect(() => tester.expectNotZoomed(tablet), throwsA(isA<TestFailure>()));
  });

  testWidgets('allows big hero numbers (rest timer)', (tester) async {
    await pump(
      tester,
      const Text(
        '1:12',
        style: TextStyle(
          fontSize: 64,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
      small,
    );
    tester.expectNotZoomed(small);
  });

  testWidgets('catches a tap target smaller than 48', (tester) async {
    await pump(
      tester,
      Center(
        child: SizedBox(
          width: 30,
          height: 30,
          child: Semantics(
            label: 'Add 2.5 kg',
            button: true,
            child: GestureDetector(onTap: () {}),
          ),
        ),
      ),
      small,
    );
    final handle = tester.ensureSemantics();
    final result = await androidTapTargetGuideline.evaluate(tester);
    expect(result.passed, isFalse);
    handle.dispose();
  });
}
