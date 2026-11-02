import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/demo.dart';

/// Builds a small plan from nothing in the editor, changes a target and
/// starts it. Starts on the home screen's "No plan yet"; ends in the
/// active workout. Shared by the device demo (integration_test/app_test.dart)
/// and the device-free run (test/features/workout/plan_editor_e2e_test.dart).
Future<void> buildPlanFlow(WidgetTester tester) async {
  Future<void> tapAndSettle(Finder finder, [int pause = 900]) async {
    await tester.ensureVisible(finder.hitTestable().first);
    await tester.pumpAndSettle();
    await tester.tap(finder.hitTestable().first);
    await tester.pumpAndSettle();
    await beat(tester, pause);
  }

  Future<void> typeName({required String ar, required String en}) async {
    await tester.enterText(find.byKey(const Key('plan_name_ar')), ar);
    await tester.pump();
    await beat(tester, 500);
    await tester.enterText(find.byKey(const Key('plan_name_en')), en);
    await tester.pump();
    await beat(tester, 700);
    await tapAndSettle(find.byKey(const Key('plan_name_save')));
  }

  final back = find.byTooltip('Back');

  // "No plan yet" → Build your plan → an empty plan.
  await tapAndSettle(find.byKey(const Key('build_plan_button')), 1200);
  expect(find.text('Your plan is empty'), findsOneWidget);

  // The first day; it opens right away.
  await tapAndSettle(find.byKey(const Key('plan_add_first_day')));
  await typeName(ar: 'صدر وتراي', en: 'Chest & Triceps');
  expect(find.text('This day is empty'), findsOneWidget);

  // Two exercises.
  await tapAndSettle(find.byKey(const Key('plan_add_exercise')));
  await typeName(ar: 'بنش بار', en: 'Bench Press');
  await tapAndSettle(find.byKey(const Key('plan_add_exercise')));
  await typeName(ar: 'حبل خلفي تراي', en: 'Rope Pushdown');
  expect(find.text('Bench Press'), findsOneWidget);
  expect(find.text('Rope Pushdown'), findsOneWidget);
  await beat(tester, 1200);

  // Bench: 4 sets instead of 3, and 5 kg plates.
  await tapAndSettle(find.text('Bench Press'), 1200);
  await tapAndSettle(find.bySemanticsLabel('One set more'), 700);
  await tapAndSettle(find.byKey(const Key('plan_step_5.0')), 1200);
  await tapAndSettle(back);
  expect(
    find.textContaining('4×12'),
    findsOneWidget,
    reason: 'the day shows the new target',
  );
  await beat(tester, 1200);

  // Back home: the new plan's first day is waiting.
  await tapAndSettle(back);
  await tapAndSettle(back, 1500);
  expect(find.text('Chest & Triceps'), findsOneWidget);
  expect(find.text('Bench Press'), findsOneWidget);

  // Start it.
  await tapAndSettle(find.text('Start workout'), 1500);
  expect(find.text('Set 1 of 4'), findsOneWidget);
}
