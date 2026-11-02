import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_theme.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_view.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../integration_test/flows/build_plan_flow.dart';

/// The plan-editor demo from integration_test/app_test.dart, on the real
/// router, controllers and on-phone storage, without a device.
void main() {
  late SharedPreferences prefs;

  Future<void> pumpApp(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1125, 2436)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workoutRepositoryProvider.overrideWithValue(
            LocalWorkoutRepository(prefs),
          ),
          clockProvider.overrideWithValue(() => DateTime(2026, 11, 2, 18)),
        ],
        child: AppUi.testWrap(
          AppScreenScale(
            builder: (context) => MaterialApp.router(
              routerConfig: appRouter,
              theme: AppTheme.light,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    appRouter.go(AppRoutes.home);
  });

  testWidgets('build a small plan, edit a target, start it', (tester) async {
    await pumpApp(tester);
    await buildPlanFlow(tester);
    expect(find.byType(ActiveWorkoutView), findsOneWidget);

    // Saved on the phone, with stable new ids.
    final plan = WorkoutPlan.fromJson(
      jsonDecode(prefs.getString(LocalWorkoutRepository.planKey)!)
          as Map<String, Object?>,
    );
    final day = plan.days.single;
    expect(day.id, startsWith('day-'));
    expect(day.exercises.map((e) => e.name.en), [
      'Bench Press',
      'Rope Pushdown',
    ]);
    final bench = day.exercises.first;
    expect(bench.id, startsWith('ex-'));
    expect(bench.targetSets, 4);
    expect(bench.weightStep, 5);
  });
}
