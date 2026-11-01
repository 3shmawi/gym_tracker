import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/settings/presentation/settings_view.dart';
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
    await (await SharedPreferences.getInstance()).clear();

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
}
