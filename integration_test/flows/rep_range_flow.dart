import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/demo.dart';

/// Sets to failure in a rep range (docs/designs/rep_ranges.md): a coach's
/// "2 sets, 6–10" on the barbell bench. Builds the plan in the editor, turns
/// on the range, logs 35×8 and 35×6, finishes, and Today keeps 35 kg (the
/// reps climb first). Starts on "No plan yet"; ends on Today. Shared by the
/// device demo (integration_test/app_test.dart) and the device-free run
/// (test/features/workout/rep_range_e2e_test.dart).
Future<void> repRangeFlow(WidgetTester tester) async {
  Future<void> tapAndSettle(Finder finder, [int pause = 900]) async {
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
    await tester.tap(finder.hitTestable().first);
    await tester.pumpAndSettle();
    await beat(tester, pause);
  }

  Future<void> tapTimes(String label, int times) async {
    for (var i = 0; i < times; i++) {
      await tester.tap(find.bySemanticsLabel(label).hitTestable().first);
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pumpAndSettle();
    await beat(tester, 600);
  }

  final back = find.byTooltip('Back');

  // A day with the barbell bench from the library.
  await tapAndSettle(find.byKey(const Key('build_plan_button')), 1200);
  await tapAndSettle(find.byKey(const Key('plan_add_first_day')));
  await tester.enterText(find.byKey(const Key('plan_name_en')), 'Chest');
  await tester.pump();
  await beat(tester, 600);
  await tapAndSettle(find.byKey(const Key('plan_name_save')));
  await tapAndSettle(find.byKey(const Key('plan_add_exercise')));
  await tapAndSettle(find.byKey(const Key('add_from_library')));
  await tester.enterText(find.byKey(const Key('library_search')), 'barbell');
  await tester.pumpAndSettle();
  await beat(tester);
  await tapAndSettle(find.byKey(const Key('library_add_flat_barbell_press')));
  await tapAndSettle(back, 700);

  // The coach's program: 2 sets, from 6 reps, a range up to 10, 5 kg steps.
  await tapAndSettle(find.text('Flat Barbell Bench Press'), 1200);
  await tapAndSettle(find.bySemanticsLabel('One set less'), 600);
  await tapTimes('One rep less', 6);
  await tapAndSettle(find.byKey(const Key('plan_rep_range_switch')), 1200);
  // On: from 6 up to 10 (the reps + 4).
  expect(find.text('Reps from'), findsOneWidget);
  await tapAndSettle(find.byKey(const Key('plan_step_5.0')), 1200);
  await tapAndSettle(back);
  expect(find.textContaining('2×6–10'), findsOneWidget);
  await beat(tester, 1200);

  // Train: 35 kg, set 1 to failure at 8, set 2 at 6.
  await tapAndSettle(back);
  await tapAndSettle(back, 1200);
  await tapAndSettle(find.byKey(const Key('home_start_button')), 1500);
  expect(find.textContaining('6–10'), findsWidgets);
  await tapTimes('Add 5 kg', 7);
  await tapTimes('One more rep', 2);
  await tapAndSettle(find.byKey(const Key('log_set_button')), 1200);
  await tapAndSettle(find.byKey(const Key('rest_skip')));
  // Set 2 starts at 35 kg and the bottom of the range: one tap.
  await tapAndSettle(find.byKey(const Key('log_set_button')), 1200);

  await tapAndSettle(find.byKey(const Key('workout_finish_menu')), 1200);
  await tapAndSettle(find.byKey(const Key('finish_confirm')), 1500);

  // Today: keep 35 kg, push the reps.
  expect(find.textContaining('2×6–10'), findsOneWidget);
  expect(find.text('→ Keep'), findsOneWidget);
}
