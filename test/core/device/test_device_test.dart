import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/device/test_device.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  void answer(Object? Function(MethodCall call) reply) =>
      messenger.setMockMethodCallHandler(
        TestDevice.channel,
        (call) async => reply(call),
      );

  tearDown(() {
    messenger.setMockMethodCallHandler(TestDevice.channel, null);
    TestDevice.isTestLab = false;
    debugDefaultTargetPlatformOverride = null;
    AppUi.debugResetLite();
  });

  group(TestDevice, () {
    test('a Google test device says so on Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final asked = <String>[];
      answer((call) {
        asked.add(call.method);
        return true;
      });
      await TestDevice.detect();
      expect(TestDevice.isTestLab, isTrue);
      expect(asked, ['isTestLab']);
    });

    test("a person's phone is not one", () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      answer((_) => false);
      await TestDevice.detect();
      expect(TestDevice.isTestLab, isFalse);
    });

    test('no answer, an odd answer or an error: not a test device', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      for (final reply in <Object? Function(MethodCall)>[
        (_) => null,
        (_) => throw PlatformException(code: 'x'),
      ]) {
        answer(reply);
        await TestDevice.detect();
        expect(TestDevice.isTestLab, isFalse);
      }
    });

    test('never asked on iOS', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      var asked = 0;
      answer((_) {
        asked++;
        return true;
      });
      await TestDevice.detect();
      expect(TestDevice.isTestLab, isFalse);
      expect(asked, 0);
    });
  });

  test('on a Google test device analytics stay off', () async {
    TestDevice.isTestLab = true;
    await Analytics.init();
    expect(Analytics.isEnabled, isFalse);
  });

  testWidgets('on a Google test device the surfaces are plain', (tester) async {
    late bool lite;
    Widget probe() => GlassAccessibilityScope(
      reduceTransparency: false,
      child: Builder(
        builder: (context) {
          lite = AppUi.isLite(context);
          return const SizedBox.shrink();
        },
      ),
    );
    await tester.pumpWidget(probe());
    expect(lite, isFalse, reason: 'glass by default');
    AppUi.forceLite();
    await tester.pumpWidget(Container(child: probe()));
    expect(lite, isTrue);
  });
}
