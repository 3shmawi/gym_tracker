import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/feature_flags/feature_flags.dart';
import 'package:gym_tracker/core/monitoring/monitoring.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/router/not_found_page.dart';
import 'package:gym_tracker/features/gym/presentation/join_page.dart';
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

/// Invite links lead to the enter-code screen only while the `gym_join` flag
/// is on; otherwise they open the home screen.
Future<String?> _joinGate(BuildContext context, GoRouterState state) async =>
    await FeatureFlags.isEnabled(Flags.gymJoin) ? null : AppRoutes.home;

/// The app's router. Deep links are handled by go_router automatically.
final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: AppRoutes.home,
  // Root navigator only. Tabs added later (StatefulShellBranch) need their
  // own `observers: Analytics.navigatorObservers` to be tracked.
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
<<<<<<< yours
      builder: (context, state) => const NextWorkoutPage(),
    ),
    GoRoute(
      path: AppRoutes.join,
      name: 'join',
      // Off (default): invite links open the home screen, as before gym
      // accounts. On: the enter-code screen.
      redirect: _joinGate,
      builder: (context, state) => const JoinPage(),
      routes: [
        GoRoute(
          path: ':code',
          name: 'join_code',
          // The code is untrusted: JoinPage parses it, shows it in the field
          // and never joins; the member has to confirm.
          builder: (context, state) =>
              JoinPage(rawCode: state.pathParameters['code']),
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
=======
      builder: (context, state) => const HomePage(),
>>>>>>> kit 1928c02
    ),
    GoRoute(
      path: AppRoutes.settings,
      name: 'settings',
      builder: (context, state) => const SettingsPage(),
    ),
  ],
  errorBuilder: (context, state) => const NotFoundPage(),
);
