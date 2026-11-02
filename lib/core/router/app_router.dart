import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/monitoring/monitoring.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/router/not_found_page.dart';
import 'package:gym_tracker/features/settings/presentation/settings_page.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_page.dart';
import 'package:gym_tracker/features/workout/presentation/exercise_history_page.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_page.dart';
import 'package:gym_tracker/features/workout/presentation/plan_day_page.dart';
import 'package:gym_tracker/features/workout/presentation/plan_exercise_page.dart';
import 'package:gym_tracker/features/workout/presentation/plan_page.dart';
import 'package:gym_tracker/features/workout/presentation/progress_page.dart';

/// Root navigator, used to show app-wide dialogs (e.g. the update dialog).
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// The app's router. Deep links are handled by go_router automatically.
final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: AppRoutes.home,
  observers: [
    ...Monitoring.navigatorObservers,
    ...Analytics.navigatorObservers,
  ],
  // Every route has a `name`: it is the screen name in analytics ($screen)
  // and monitoring. Without one a nested route reports only its own path
  // piece (e.g. ':exerciseId'). Names are stable; never put ids in them.
  routes: [
    GoRoute(
      path: AppRoutes.home,
      name: 'home',
      builder: (context, state) => const NextWorkoutPage(),
    ),
    GoRoute(
      path: AppRoutes.join,
      name: 'join_root',
      // Only `/join/<code>` is a link; a bare `/join` is not found.
      builder: (context, state) => const NotFoundPage(),
      routes: [
        GoRoute(
          path: ':code',
          name: 'join',
          // The code is untrusted and unused: go home, change nothing.
          redirect: (context, state) => AppRoutes.home,
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.workout,
      name: 'workout',
      builder: (context, state) => const ActiveWorkoutPage(),
    ),
    GoRoute(
      path: AppRoutes.progress,
      name: 'progress',
      builder: (context, state) => const ProgressPage(),
      routes: [
        GoRoute(
          path: ':exerciseId',
          name: 'exercise_history',
          builder: (context, state) => ExerciseHistoryPage(
            exerciseId: state.pathParameters['exerciseId']!,
          ),
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.plan,
      name: 'plan',
      builder: (context, state) => const PlanPage(),
      routes: [
        GoRoute(
          path: ':dayId',
          name: 'plan_day',
          builder: (context, state) =>
              PlanDayPage(dayId: state.pathParameters['dayId']!),
          routes: [
            GoRoute(
              path: ':exerciseId',
              name: 'plan_exercise',
              builder: (context, state) => PlanExercisePage(
                dayId: state.pathParameters['dayId']!,
                exerciseId: state.pathParameters['exerciseId']!,
              ),
            ),
          ],
        ),
      ],
    ),
    GoRoute(
      path: AppRoutes.settings,
      name: 'settings',
      builder: (context, state) => const SettingsPage(),
    ),
  ],
  errorBuilder: (context, state) => const NotFoundPage(),
);
