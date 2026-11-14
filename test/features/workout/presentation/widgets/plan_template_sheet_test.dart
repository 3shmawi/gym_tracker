import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/plan_template_sheet.dart';

import '../../../../helpers/pump_app.dart';
import '../../../../helpers/ui_check.dart';

/// Opens the sheet from a button, like the no-plan screen does.
class _Opener extends StatelessWidget {
  const new({required this.onResult});

  final ValueChanged<PlanTemplateId?> onResult;

  @override
  Widget build(BuildContext context) => AppScaffold(
    body: Center(
      child: AppPrimaryButton(
        label: 'Open',
        onPressed: () async => onResult(await showPlanTemplateSheet(context)),
      ),
    ),
  );
}

/// The picker on a screen-sized surface, as it looks over the home screen.
class _Shown extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => AppScaffold(
    body: Align(
      alignment: AlignmentDirectional.bottomCenter,
      child: Material(child: PlanTemplatePicker(onPick: (_) {})),
    ),
  );
}

void main() {
  for (final template in PlanTemplateId.values) {
    testWidgets('picking ${template.id} returns it', (tester) async {
      PlanTemplateId? result;
      var done = false;
      await tester.pumpApp(
        _Opener(
          onResult: (r) {
            result = r;
            done = true;
          },
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(Key('template_${template.id}')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('template_${template.id}')));
      await tester.pumpAndSettle();
      expect(done, isTrue);
      expect(result, template);
    });
  }

  testWidgets('closing the sheet picks nothing', (tester) async {
    PlanTemplateId? result = PlanTemplateId.split5;
    await tester.pumpApp(_Opener(onResult: (r) => result = r));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    // Back, as the system back button or the swipe does.
    Navigator.of(tester.element(find.byType(PlanTemplatePicker))).pop();
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('each plan names its days, in the app language', (tester) async {
    await tester.pumpApp(const _Shown());
    expect(
      find.textContaining('Full Body A · Full Body B · Full Body C'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Upper 1 · Lower 1 · Upper 2 · Lower 2'),
      findsOneWidget,
    );
    expect(find.text(l10nEn.planTemplateFullBody), findsOneWidget);
    expect(find.text(l10nEn.planTemplateUpperLower), findsOneWidget);
    expect(find.text(l10nEn.planTemplateSplit5), findsOneWidget);
  });

  testWidgets('day names follow the app language (Arabic)', (tester) async {
    await tester.pumpApp(const _Shown(), locale: const Locale('ar'));
    expect(
      find.textContaining('جسم كامل أ · جسم كامل ب · جسم كامل ج'),
      findsOneWidget,
    );
  });

  testWidgets('a screen reader hears each plan as one button', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpApp(const _Shown());
    expect(
      find.bySemanticsLabel(
        RegExp('^${RegExp.escape(l10nEn.planTemplateFullBody)}'),
      ),
      findsOneWidget,
    );
    handle.dispose();
  });

  screensUiTests({'plan_template_sheet': () => const _Shown()});
}
