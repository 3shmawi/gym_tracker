import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/backend/backend.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/monitoring/monitoring.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/router/router_refresh.dart';
import 'package:gym_tracker/core/splash/animated_splash.dart';
import 'package:gym_tracker/core/theme/app_fonts.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';

/// Starts monitoring first, then shows the animated splash at once while
/// every core service initialises, then the app. Anything that fails during
/// start-up is reported, and the app still opens.
///
/// Completes when start-up work is done (the splash may still be playing).
Future<void> bootstrap(Widget Function() builder) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppFonts.registerLicenses();
  Future<void>? ready;
  await Monitoring.run(() async {
    ready = _startServices();
    return AnimatedSplash(ready: ready!, app: (_) => AppUi.wrap(builder()));
  });
  await ready;
}

/// Same order as before the splash existed; each step is reported on
/// failure and the next one still runs.
Future<void> _startServices() async {
  for (final step in <Future<void> Function()>[
    Backend.init,
    Analytics.init,
    Dependencies.init,
    _followSession,
    openWorkoutFromRestAlarm,
    AppUi.initialize,
  ]) {
    try {
      await step();
    } on Object catch (error, stackTrace) {
      await Monitoring.captureException(error, stackTrace);
    }
  }
}

/// Redirects run again when the sign-in session starts or ends.
Future<void> _followSession() async =>
    routerRefresh.attach(Dependencies.accountRepository.sessionChanges);

/// Tapping "Rest over" after the app was killed opens the workout, not
/// home. Only this one route: the notification's payload is never read.
@visibleForTesting
Future<void> openWorkoutFromRestAlarm() async {
  if (await Dependencies.restAlarm.openedApp()) appRouter.go(AppRoutes.workout);
}
