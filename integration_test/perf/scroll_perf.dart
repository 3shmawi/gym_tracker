// Scroll performance of the main lists: frame build and raster times while
// each list is flung up and down. Not a `_test.dart` file on purpose:
// `flutter test integration_test` (the CI integration job) skips it, so CI
// is not slower. Run it in profile mode on a device (docs/performance.md):
//
//   ./scripts/perf.sh                       # glass (the real look)
//   ./scripts/perf.sh --lite                # GLASS_LITE=true, to compare
//
// Each flow is recorded with `watchPerformance` (FrameTiming from the
// engine); `test_driver/perf_driver.dart` writes the summary to
// build/perf/<mode>.json and a table to build/perf/<mode>.md.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_view.dart';
import 'package:gym_tracker/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_test.dart' show freshInstall, useFakeRestAlarm;

/// The plan day with the most exercises (Shoulders & Arms, 9).
const _day = 'day-2';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('scroll performance of the main lists', (tester) async {
    await freshInstall(tester);
    await _seedHistory();
    await app.main();
    useFakeRestAlarm();
    await tester.pumpAndSettle();
    binding.reportData = {
      'meta': {
        'mode': AppUi.lite ? 'lite' : 'glass',
        'platform': Platform.operatingSystem,
        'build': kProfileMode
            ? 'profile'
            : kReleaseMode
            ? 'release'
            : 'debug',
      },
    };

    // The waiting day is day 2 (two sessions of day 1 are in the history).
    await _measure(tester, binding, 'home', AppRoutes.home);
    await _measure(tester, binding, 'plan_day', AppRoutes.planDay(_day));
    await _measure(tester, binding, 'library', AppRoutes.libraryFor(_day));
    await _measure(
      tester,
      binding,
      'exercise_screen',
      AppRoutes.libraryExercise('db_shoulder_press'),
    );
    await _measure(tester, binding, 'progress', AppRoutes.progress);
    await _measure(
      tester,
      binding,
      'exercise_history',
      AppRoutes.exerciseHistory('db_shoulder_press'),
    );

    // The active workout: started from home like a member would.
    appRouter.go(AppRoutes.home);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('home_start_button')));
    await tester.pumpAndSettle();
    expect(find.byType(ActiveWorkoutView), findsOneWidget);
    await _fling(tester, binding, 'active_workout');
  });
}

Future<void> _measure(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
  String route,
) async {
  appRouter.go(route);
  await tester.pumpAndSettle();
  await _fling(tester, binding, name);
}

/// Three flings down and back up on the screen's main list: the same
/// gesture every run, so runs can be compared.
Future<void> _fling(
  WidgetTester tester,
  IntegrationTestWidgetsFlutterBinding binding,
  String name,
) async {
  final list = find.byType(Scrollable).hitTestable().first;
  await binding.watchPerformance(() async {
    for (var i = 0; i < 3; i++) {
      await tester.fling(list, const Offset(0, -500), 2500);
      await tester.pumpAndSettle();
      await tester.fling(list, const Offset(0, 500), 2500);
      await tester.pumpAndSettle();
    }
  }, reportKey: name);
}

/// Six weeks of training on the 5-day plan with every set logged, so
/// progress and history have long lists. The last session was day 1, so
/// day 2 (the longest day) is waiting.
Future<void> _seedHistory() async {
  final repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
  const plan = PlanTemplates.fiveDaySplit;
  await repo.savePlan(plan);
  final start = DateTime.now().subtract(const Duration(days: 43));
  for (var i = 0; i < 26; i++) {
    final day = plan.days[i % plan.days.length];
    await repo.saveSession(
      WorkoutSession(
        dayId: day.id,
        finishedAt: start.add(Duration(days: i + (i ~/ 5) * 2, hours: 18)),
        sets: [
          for (final e in day.exercises)
            for (var s = 0; s < e.targetSets; s++)
              LoggedSet(
                exerciseId: e.id,
                weight: 10.0 + i * 2.5,
                reps: e.targetReps,
              ),
        ],
      ),
    );
  }
}
