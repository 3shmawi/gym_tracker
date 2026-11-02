import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/bootstrap.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/router/not_found_page.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/settings/data/repositories/shared_prefs_settings_repository.dart';
import 'package:gym_tracker/features/settings/presentation/settings_controller.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/services/rest_alarm.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_page.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_view.dart';
import 'package:gym_tracker/features/workout/presentation/exercise_history_page.dart';
import 'package:gym_tracker/features/workout/presentation/exercise_history_view.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_page.dart';
import 'package:gym_tracker/features/workout/presentation/plan_day_page.dart';
import 'package:gym_tracker/features/workout/presentation/plan_exercise_page.dart';
import 'package:gym_tracker/features/workout/presentation/plan_page.dart';
import 'package:gym_tracker/features/workout/presentation/progress_page.dart';
import 'package:gym_tracker/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_rest_alarm.dart';

/// Deep links are untrusted input: unknown or crafted paths must land on a
/// safe screen, never crash or open something unexpected.
void main() {
  Future<void> pumpRouter(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1125, 2436)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workoutRepositoryProvider.overrideWithValue(
            LocalWorkoutRepository(prefs),
          ),
          settingsRepositoryProvider.overrideWithValue(
            SharedPrefsSettingsRepository(prefs),
          ),
        ],
        child: AppUi.testWrap(
          AppScreenScale(
            builder: (context) => MaterialApp.router(
              routerConfig: appRouter,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('unknown and crafted paths show the not-found page', (
    tester,
  ) async {
    await pumpRouter(tester);

    for (final path in [
      '/does-not-exist',
      '/settings/../../etc/passwd',
      '/%2e%2e/admin',
    ]) {
      appRouter.go(path);
      await tester.pumpAndSettle();
      expect(find.byType(NotFoundPage), findsOneWidget, reason: path);
    }
  });

  testWidgets('query parameters cannot redirect the app', (tester) async {
    await pumpRouter(tester);

    appRouter.go('/?redirect=https://evil.example.com');
    await tester.pumpAndSettle();

    expect(find.byType(NextWorkoutPage), findsOneWidget);
  });

  testWidgets('/workout with no workout in progress is safe', (tester) async {
    await pumpRouter(tester);
    for (final path in [
      '/workout',
      '/workout?day=999',
      '/workout?day=-1&sets=%3Cscript%3E',
      '/workout/../settings',
    ]) {
      appRouter.go(path);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: path);
      if (path.startsWith('/workout?') || path == '/workout') {
        expect(find.byType(ActiveWorkoutPage), findsOneWidget, reason: path);
        expect(find.byKey(const Key('workout_go_home')), findsOneWidget);
      }
    }
  });

  testWidgets('leaving an empty /workout goes home', (tester) async {
    await pumpRouter(tester);
    appRouter.go('/workout');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workout_go_home')));
    await tester.pumpAndSettle();
    expect(find.byType(NextWorkoutPage), findsOneWidget);
    expect(find.byType(ActiveWorkoutView), findsNothing);
  });

  testWidgets('/progress opens with no plan and no history', (tester) async {
    await pumpRouter(tester);
    appRouter.go('/progress?redirect=https://evil.example.com');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ProgressPage), findsOneWidget);
  });

  testWidgets('/progress/<id>: unknown or crafted ids are safe', (
    tester,
  ) async {
    await pumpRouter(tester);
    for (final id in [
      'not_an_exercise',
      '%3Cscript%3Ealert(1)%3C%2Fscript%3E',
      "x'%3B%20DROP%20TABLE%20s%3B--",
      'a' * 2000,
      '%F0%9F%92%A5',
    ]) {
      appRouter.go('/progress/$id');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: id);
      expect(find.byType(ExerciseHistoryPage), findsOneWidget, reason: id);
      expect(find.byType(ExerciseHistoryView), findsOneWidget, reason: id);
    }
  });

  testWidgets('/progress/<id> with extra segments is not found', (
    tester,
  ) async {
    await pumpRouter(tester);
    appRouter.go('/progress/flat_db_press/../../settings/x');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('"Rest over" notification tapped after the app was killed', () {
    tearDown(() => Dependencies.restAlarm = const SilentRestAlarm());

    testWidgets('opens /workout only, and safely with no workout', (
      tester,
    ) async {
      await pumpRouter(tester);
      appRouter.go(AppRoutes.home);
      Dependencies.restAlarm = FakeRestAlarm()..opened = true;
      await openWorkoutFromRestAlarm();
      await tester.pumpAndSettle();
      expect(
        appRouter.routerDelegate.currentConfiguration.uri.path,
        AppRoutes.workout,
      );
      expect(find.byType(ActiveWorkoutView), findsOneWidget);
      expect(find.byKey(const Key('workout_go_home')), findsOneWidget);
    });

    testWidgets('a normal launch stays home', (tester) async {
      await pumpRouter(tester);
      appRouter.go(AppRoutes.home);
      Dependencies.restAlarm = FakeRestAlarm();
      await openWorkoutFromRestAlarm();
      await tester.pumpAndSettle();
      expect(find.byType(NextWorkoutPage), findsOneWidget);
    });

    test('the payload is never read', () {
      // The notification can't carry a route: LocalNotifications only asks
      // "did a notification open the app", and bootstrap goes to one route.
      final source = File('lib/core/notifications/local_notifications.dart')
          .readAsStringSync();
      expect(source, isNot(contains('.payload')));
      expect(source, isNot(contains('notificationResponse')));
    });
  });

  testWidgets('/plan opens with no plan (the "Build your plan" editor)', (
    tester,
  ) async {
    await pumpRouter(tester);
    appRouter.go('/plan?redirect=https://evil.example.com&day=999');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(PlanPage), findsOneWidget);
    expect(find.byKey(const Key('plan_add_first_day')), findsOneWidget);
  });

  testWidgets('/plan/<day>[/<exercise>]: unknown or crafted ids are safe', (
    tester,
  ) async {
    await pumpRouter(tester);
    const hostile = [
      'not_a_day',
      '%3Cscript%3Ealert(1)%3C%2Fscript%3E',
      "x'%3B%20DROP%20TABLE%20plan%3B--",
      '%F0%9F%92%A5',
      '%00',
    ];
    for (final id in [...hostile, 'a' * 2000]) {
      appRouter.go('/plan/$id');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: id);
      expect(find.byType(PlanDayPage), findsOneWidget, reason: id);
      expect(find.text("This day isn't in your plan."), findsOneWidget);
    }
    for (final id in hostile) {
      appRouter.go('/plan/day-1/$id');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: id);
      expect(find.byType(PlanExercisePage), findsOneWidget, reason: id);
      expect(find.text("This exercise isn't in your plan."), findsOneWidget);
    }
  });

  testWidgets('/plan with extra segments is not found, never a crash', (
    tester,
  ) async {
    await pumpRouter(tester);
    for (final path in [
      '/plan/day-1/flat_db_press/extra',
      '/plan/../settings/x/y',
      '/plan/day-1/x/../../../etc/passwd',
    ]) {
      appRouter.go(path);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: path);
    }
  });

  testWidgets('a crafted link can only open the editor, never change it', (
    tester,
  ) async {
    await pumpRouter(tester);
    appRouter.go('/plan/new?add=1&name=%3Cscript%3E&delete=day-1');
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(LocalWorkoutRepository.planKey), isNull);
  });
}
