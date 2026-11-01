import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/settings/presentation/settings_view.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_view.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_page.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/exercise_preview_row.dart';
import 'package:gym_tracker/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/demo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first launch: pick the 5-day plan and see the next workout', (
    tester,
  ) async {
    // A fresh install: no plan, no history.
    await freshInstall(tester);

    await app.main();
    await tester.pumpAndSettle();
    await beat(tester, 1500);

    expect(find.byType(NextWorkoutPage), findsOneWidget);
    await tester.tap(find.byKey(const Key('use_template_button')));
    await tester.pumpAndSettle();
    await beat(tester, 1500);

    // Day 1 of 5, Chest & Back, all seven exercises, first time for each.
    expect(find.byType(ExercisePreviewRow), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await beat(tester, 1200);
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    await beat(tester);

    await tester.tap(find.byKey(const Key('home_settings_button')));
    await tester.pumpAndSettle();
    await beat(tester);
    expect(find.byType(SettingsView), findsOneWidget);
    await beat(tester, 1500);
  });

  testWidgets('leg day: pick day 3, log sets, rest, finish', (tester) async {
    await freshInstall(tester);
    await app.main();
    await tester.pumpAndSettle();
    await beat(tester);

    await tester.tap(find.byKey(const Key('use_template_button')));
    await tester.pumpAndSettle();
    await beat(tester);

    // Tomorrow is legs: choose day 3.
    debugPrint(
      'home pages: ${find.byType(NextWorkoutPage).evaluate().length}, '
      'settings: ${find.byType(SettingsView).evaluate().length}, '
      'change day buttons: '
      '${find.byKey(const Key('change_day_button')).evaluate().length}',
    );
    await tester.tap(find.byKey(const Key('change_day_button')).hitTestable());
    await tester.pumpAndSettle();
    await beat(tester);
    await tester.tap(find.byKey(const Key('choose_day_2')).hitTestable());
    await tester.pumpAndSettle();
    await beat(tester, 1200);

    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
    expect(find.byType(ActiveWorkoutView), findsOneWidget);
    await beat(tester);

    // Squat set 1: add 20 kg (4 × 5 kg), one tap to log.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.bySemanticsLabel('Add 5 kg'));
      await tester.pump(const Duration(milliseconds: 250));
    }
    await beat(tester);
    await tester.tap(find.byKey(const Key('log_set_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rest_countdown')), findsOneWidget);
    await beat(tester, 2000);

    await tester.tap(find.byKey(const Key('rest_add_15')));
    await tester.pump();
    await beat(tester);
    await tester.tap(find.byKey(const Key('rest_skip')));
    await tester.pumpAndSettle();
    await beat(tester);

    // Set 2 is prefilled with set 1's weight: one tap.
    await tester.tap(find.byKey(const Key('log_set_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rest_skip')));
    await tester.pumpAndSettle();
    await beat(tester);

    await tester.tap(find.byKey(const Key('workout_finish_menu')));
    await tester.pumpAndSettle();
    await beat(tester, 1500);
    await tester.tap(find.byKey(const Key('finish_confirm')));
    await tester.pumpAndSettle();
    await beat(tester);

    // Back home: the plan moved on to day 4.
    expect(find.text('Day 4 of 5'), findsOneWidget);
    await beat(tester, 1500);
  });
}

/// A fresh install for each test: unmount the previous test's app (runApp
/// with the same root widget would keep its state, e.g. the ProviderScope),
/// send the app-wide router back home and clear everything saved on the
/// device.
Future<void> freshInstall(WidgetTester tester) async {
  // Pop back home while the previous app is still mounted, so no page of
  // it (e.g. Settings) is left in the router to cover the new one.
  appRouter.go(AppRoutes.home);
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await (await SharedPreferences.getInstance()).clear();
}
