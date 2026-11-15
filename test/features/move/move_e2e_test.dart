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

  Future<void> pumpApp(WidgetTester tester) async {
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
  }

  testWidgets('home → Move → 10 push-ups → saved → history', (tester) async {
    await pumpApp(tester);

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

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder.first);
    await tester.pumpAndSettle();
    await tester.tap(finder.hitTestable().first);
    await tester.pumpAndSettle();
  }

  // "Play again" opened the same route with the same launch: the round's
  // controller (keyed by the launch) was never thrown away, so the results
  // came back and nothing started (owner's report, 2026-11-15).
  testWidgets('play again after a camera round starts a new round', (
    tester,
  ) async {
    await pumpApp(tester);
    await tap(tester, find.byKey(const Key('home_menu_button')));
    await tap(tester, find.byKey(const Key('home_move_button')));
    await tap(tester, find.byKey(const Key('move_round_r10')));
    await tap(tester, find.byKey(const Key('move_hub_camera')));
    // The tip and "why the camera" show only until they were seen once.
    for (
      var i = 0;
      i < 2 && find.byKey(const Key('move_setup_next')).evaluate().isNotEmpty;
      i++
    ) {
      await tap(tester, find.byKey(const Key('move_setup_next')));
    }
    await waitFor(tester, find.byKey(const Key('move_results_again')));
    await tester.pumpAndSettle();

    await tap(tester, find.byKey(const Key('move_results_again')));
    expect(find.byKey(const Key('move_results_again')), findsNothing);
    // A new camera, placement, 3-2-1 and a whole new round.
    await waitFor(tester, find.byKey(const Key('move_countdown')));
    await waitFor(tester, find.byKey(const Key('move_results_save')));
    await tester.pumpAndSettle();
    expect(find.text('10'), findsWidgets);
  });

  testWidgets('play again after counting by hand starts a new round', (
    tester,
  ) async {
    await pumpApp(tester);
    await tap(tester, find.byKey(const Key('home_menu_button')));
    await tap(tester, find.byKey(const Key('home_move_button')));
    await tap(tester, find.byKey(const Key('move_round_r10')));
    await tap(tester, find.byKey(const Key('move_hub_manual')));
    await tap(tester, find.byKey(const Key('move_manual_start')));
    await wait(tester, const Duration(seconds: 4));
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byKey(const Key('move_manual_tap')));
      await tester.pump(const Duration(milliseconds: 300));
    }
    await waitFor(tester, find.byKey(const Key('move_results_again')));
    await tester.pumpAndSettle();

    await tap(tester, find.byKey(const Key('move_results_again')));
    expect(find.byKey(const Key('move_results_again')), findsNothing);
    // A whole second round, to its results.
    await tap(tester, find.byKey(const Key('move_manual_start')));
    await wait(tester, const Duration(seconds: 4));
    for (var i = 0; i < 10; i++) {
      await tester.tap(find.byKey(const Key('move_manual_tap')));
      await tester.pump(const Duration(milliseconds: 300));
    }
    await waitFor(tester, find.byKey(const Key('move_results_save')));
  });
}
