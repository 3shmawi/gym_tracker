import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/feature_flags/feature_flags.dart';
import 'package:gym_tracker/core/monitoring/monitoring.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/router/link_guard.dart';
import 'package:gym_tracker/core/router/not_found_page.dart';
import 'package:gym_tracker/core/router/router_refresh.dart';
import 'package:gym_tracker/features/backup/presentation/backup_sign_in_page.dart';
import 'package:gym_tracker/features/gym/presentation/delete_account_page.dart';
import 'package:gym_tracker/features/gym/presentation/join_page.dart';
import 'package:gym_tracker/features/gym/presentation/joined_page.dart';
import 'package:gym_tracker/features/gym/presentation/profile_page.dart';
import 'package:gym_tracker/features/gym/presentation/scanner_page.dart';
import 'package:gym_tracker/features/gym/presentation/welcome_page.dart';
import 'package:gym_tracker/features/library/presentation/exercise_guide_page.dart';
import 'package:gym_tracker/features/library/presentation/library_page.dart';
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

/// Backup shows only while the `training_backup` flag is on; otherwise a
/// link to it opens the home screen.
Future<String?> _backupGate(BuildContext context, GoRouterState state) async =>
    await FeatureFlags.isEnabled(Flags.trainingBackup) ? null : AppRoutes.home;

/// Screens that only make sense with an account (profile, delete account):
/// signed-out people go to the "how do you want to start?" screen. With the
/// flag off they open the home screen like every other gym link.
Future<String?> _accountGate(BuildContext context, GoRouterState state) async {
  final gate = await _joinGate(context, state);
  if (gate != null) return gate;
  return Dependencies.accountRepository.session.isSignedIn
      ? null
      : AppRoutes.welcome;
}

/// First launch with gym accounts on: ask "join a gym or train alone?" once.
/// People who already have a plan, or an account, are never asked.
Future<String?> _homeGate(BuildContext context, GoRouterState state) async {
  try {
    if (!await FeatureFlags.isEnabled(Flags.gymJoin)) return null;
    if (Dependencies.accountRepository.session.isSignedIn) return null;
    final local = Dependencies.gymLocalRepository;
    final done = switch (await local.loadOnboardingDone()) {
      Success(:final value) => value,
      Failed() => true,
    };
    if (done) return null;
    final plan = await Dependencies.workoutRepository.loadPlan();
    if (plan case Success(:final value) when value != null) {
      await local.saveOnboardingDone();
      return null;
    }
    return AppRoutes.welcome;
    // The start-up check must never block the app from opening.
  } on Object {
    return null;
  }
}

/// The app's router. Deep links are handled by go_router automatically.
final appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  // The link that opened the app, if it can be decoded (`LinkGuard`).
  initialLocation: LinkGuard.initialLocation(),
  overridePlatformDefaultLocation: true,
  refreshListenable: routerRefresh,
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
      redirect: _homeGate,
      builder: (context, state) => const NextWorkoutPage(),
    ),
    GoRoute(
      path: AppRoutes.welcome,
      name: 'welcome',
      redirect: _joinGate,
      builder: (context, state) => const WelcomePage(),
    ),
    GoRoute(
      path: AppRoutes.backup,
      name: 'backup',
      redirect: _backupGate,
      builder: (context, state) => const BackupSignInPage(),
    ),
    GoRoute(
      path: AppRoutes.profile,
      name: 'profile',
      redirect: _accountGate,
      builder: (context, state) => const ProfilePage(),
      routes: [
        GoRoute(
          path: 'delete',
          name: 'profile_delete',
          builder: (context, state) => const DeleteAccountPage(),
        ),
      ],
    ),
    // Each join screen is its own top-level route (not a child of `/join`):
    // a child would stack on top of an empty enter-code screen, and both
    // would react to the same join result. `scan` and `joined` come before
    // `:code`, so they are never read as codes.
    GoRoute(
      path: AppRoutes.join,
      name: 'join',
      // Off (default): invite links open the home screen, as before gym
      // accounts. On: the enter-code screen.
      redirect: _joinGate,
      builder: (context, state) => const JoinPage(),
    ),
    GoRoute(
      path: AppRoutes.joinScan,
      name: 'join_scan',
      redirect: _joinGate,
      builder: (context, state) => const ScannerPage(),
    ),
    GoRoute(
      path: AppRoutes.joined,
      name: 'join_joined',
      redirect: _joinGate,
      builder: (context, state) => const JoinedPage(),
    ),
    GoRoute(
      path: '${AppRoutes.join}/:code',
      name: 'join_code',
      redirect: _joinGate,
      // The code is untrusted: JoinPage parses it, shows it in the field
      // and never joins; the member has to confirm.
      builder: (context, state) =>
          JoinPage(rawCode: state.pathParameters['code']),
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
      path: AppRoutes.library,
      name: 'exercise_library',
      builder: (context, state) =>
          LibraryPage(dayId: state.uri.queryParameters['day']),
      routes: [
        GoRoute(
          path: ':exerciseId',
          name: 'library_exercise',
          builder: (context, state) => ExerciseGuidePage(
            exerciseId: state.pathParameters['exerciseId']!,
            dayId: state.uri.queryParameters['day'],
          ),
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
