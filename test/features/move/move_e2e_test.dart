import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/feature_flags/feature_flags.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_theme.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/move/data/repositories/prefs_move_local_repository.dart';
import 'package:gym_tracker/features/move/presentation/move_providers.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../integration_test/flows/move_flow.dart';

/// The Move games demo from integration_test/app_test.dart, on the real
/// router, controllers, detector and on-phone storage, without a device
/// (the camera is the recorded set).
void main() {
  late LocalWorkoutRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
    await repo.savePlan(PlanTemplates.fiveDaySplit);
    FeatureFlags.overrides[Flags.moveGames] = true;
    Dependencies.moveLocalRepository = InMemoryMoveLocalRepository();
    Dependencies.poseSource = demoPoseSource;
    appRouter.go(AppRoutes.home);
  });

  tearDown(FeatureFlags.overrides.clear);

  testWidgets('home → Move → 10 push-ups → saved → history', (tester) async {
    tester.view
      ..physicalSize = const Size(1125, 2436)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workoutRepositoryProvider.overrideWithValue(repo),
          // Rounds follow the test's clock.
          moveClockProvider.overrideWithValue(() => tester.binding.clock.now()),
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

    await moveFlow(tester);

    final saved = switch (await repo.loadHistory()) {
      Success(:final value) => value,
      Failed(:final failure) => throw failure,
    };
    final round = saved.single;
    expect(round.dayId, WorkoutSession.moveDayId);
    expect(round.sets.single.exerciseId, 'push_ups');
    expect(round.sets.single.reps, 10);
  });
}
