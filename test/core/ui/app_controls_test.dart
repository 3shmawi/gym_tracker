import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/ui_check.dart';

/// The logging dock from the design (Active workout, Wide Lat Pulldown,
/// set 2 of 3), built only from the shared controls.
class _LogDockShowcase extends StatefulWidget {
  const new();

  @override
  State<_LogDockShowcase> createState() => _LogDockShowcaseState();
}

class _LogDockShowcaseState extends State<_LogDockShowcase> {
  double weight = 52.5;
  int reps = 12;

  String get w => weight.toStringAsFixed(weight % 1 == 0 ? 0 : 1);

  @override
  Widget build(BuildContext context) => AppScaffold(
    body: SingleChildScrollView(
      padding: EdgeInsets.all(AppDimens.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppDimens.sm2,
        children: [
          const Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              AppBadge(label: '↑ Increase', tone: AppTone.up),
              AppBadge(label: '→ Keep', tone: AppTone.keep),
              AppBadge(label: '↓ Decrease', tone: AppTone.down),
              AppBadge(label: 'First time', tone: AppTone.fresh),
            ],
          ),
          Wrap(
            spacing: 6,
            children: [
              AppSetChip(
                label: '52.5×12',
                state: AppSetState.done,
                semanticLabel: 'Set 1, 52.5 kg, 12 reps, logged',
                onTap: () {},
              ),
              const AppSetChip(
                label: 'Set 2',
                state: AppSetState.current,
                semanticLabel: 'Set 2, now',
              ),
              const AppSetChip(
                label: '3',
                state: AppSetState.pending,
                semanticLabel: 'Set 3, to do',
              ),
            ],
          ),
          AppStepper(
            value: w,
            unit: 'kg',
            decrementLabel: 'Remove 2.5 kg',
            incrementLabel: 'Add 2.5 kg',
            onDecrement: () => setState(() => weight -= 2.5),
            onIncrement: () => setState(() => weight += 2.5),
          ),
          AppStepper(
            value: '$reps',
            unit: 'reps',
            decrementLabel: 'One rep less',
            incrementLabel: 'One rep more',
            onDecrement: () => setState(() => reps--),
            onIncrement: () => setState(() => reps++),
          ),
          AppPrimaryButton(
            label: 'Log $w × $reps',
            icon: Icons.check,
            onPressed: () {},
          ),
          AppSecondaryButton(label: 'Skip rest', onPressed: () {}),
        ],
      ),
    ),
  );
}

void main() {
  group(AppStepper, () {
    Widget stepper({VoidCallback? onInc, VoidCallback? onDec}) => Scaffold(
      body: Center(
        child: AppStepper(
          value: '52.5',
          unit: 'kg',
          decrementLabel: 'Remove 2.5 kg',
          incrementLabel: 'Add 2.5 kg',
          onDecrement: onDec,
          onIncrement: onInc,
        ),
      ),
    );

    testWidgets('steps once per tap', (tester) async {
      var inc = 0;
      var dec = 0;
      await tester.pumpApp(stepper(onInc: () => inc++, onDec: () => dec++));
      await tester.tap(find.bySemanticsLabel('Add 2.5 kg'));
      await tester.tap(find.bySemanticsLabel('Add 2.5 kg'));
      await tester.tap(find.bySemanticsLabel('Remove 2.5 kg'));
      expect(inc, 2);
      expect(dec, 1);
    });

    testWidgets('repeats while held and stops on release', (tester) async {
      var inc = 0;
      await tester.pumpApp(stepper(onInc: () => inc++, onDec: () {}));
      final gesture = await tester.startGesture(
        tester.getCenter(find.bySemanticsLabel('Add 2.5 kg')),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.up();
      final afterRelease = inc;
      expect(afterRelease, greaterThanOrEqualTo(4));
      await tester.pump(const Duration(seconds: 1));
      expect(inc, afterRelease, reason: 'no steps after release');
    });

    testWidgets('keys are at least 56 px (logging controls)', (tester) async {
      await tester.pumpApp(stepper(onInc: () {}, onDec: () {}));
      final key = tester.getSize(find.bySemanticsLabel('Add 2.5 kg'));
      expect(key.width, greaterThanOrEqualTo(56));
      expect(key.height, greaterThanOrEqualTo(56));
    });

    testWidgets('reads the value with its unit', (tester) async {
      await tester.pumpApp(stepper(onInc: () {}, onDec: () {}));
      expect(find.bySemanticsLabel('52.5 kg'), findsOneWidget);
    });

    testWidgets('a disabled key is announced as disabled', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpApp(stepper(onInc: () {}));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Remove 2.5 kg')),
        isSemantics(isButton: true, hasEnabledState: true, isEnabled: false),
      );
      await tester.tap(find.bySemanticsLabel('Remove 2.5 kg'));
      expect(tester.takeException(), isNull);
      handle.dispose();
    });
  });

  group(AppPrimaryButton, () {
    testWidgets('calls back and is at least 56 high', (tester) async {
      var pressed = 0;
      await tester.pumpApp(
        Scaffold(
          body: Center(
            child: AppPrimaryButton(
              label: 'Log 52.5 × 12',
              onPressed: () => pressed++,
            ),
          ),
        ),
      );
      await tester.tap(find.text('Log 52.5 × 12'));
      expect(pressed, 1);
      expect(
        tester.getSize(find.byType(AppPrimaryButton)).height,
        greaterThanOrEqualTo(56),
      );
    });

    testWidgets('ignores taps when disabled', (tester) async {
      await tester.pumpApp(
        const Scaffold(
          body: AppPrimaryButton(label: 'Finish', onPressed: null),
        ),
      );
      await tester.tap(find.text('Finish'));
      expect(tester.takeException(), isNull);
    });
  });

  group(AppSetChip, () {
    testWidgets('a logged set opens for editing', (tester) async {
      var tapped = false;
      await tester.pumpApp(
        Scaffold(
          body: Center(
            child: AppSetChip(
              label: '52.5×12',
              state: AppSetState.done,
              semanticLabel: 'Set 1, 52.5 kg, 12 reps, logged',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );
      await tester.tap(
        find.bySemanticsLabel('Set 1, 52.5 kg, 12 reps, logged'),
      );
      expect(tapped, isTrue);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });
  });

  testWidgets('steppers update the log button in place', (tester) async {
    await tester.pumpApp(const _LogDockShowcase());
    await tester.tap(find.bySemanticsLabel('Add 2.5 kg'));
    await tester.tap(find.bySemanticsLabel('One rep less'));
    await tester.pump();
    expect(find.text('Log 55 × 11'), findsOneWidget);
  });

  screenUiTests('log_dock', () => const _LogDockShowcase());
}
