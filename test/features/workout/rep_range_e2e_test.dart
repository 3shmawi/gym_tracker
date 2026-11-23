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
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../integration_test/flows/rep_range_flow.dart';

/// The rep-range demo from integration_test/app_test.dart, on the real
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

  testWidgets('a rep range: 2×6–10, log 35×8 and 35×6, keep 35', (
    tester,
  ) async {
    await pumpApp(tester);
    await repRangeFlow(tester);

    final plan = WorkoutPlan.fromJson(
      jsonDecode(prefs.getString(LocalWorkoutRepository.planKey)!)
          as Map<String, Object?>,
    );
    final bench = plan.days.single.exercises.single;
    expect(bench.id, 'flat_barbell_press');
    expect((bench.targetSets, bench.targetReps, bench.repsTop), (2, 6, 10));
  });
}
