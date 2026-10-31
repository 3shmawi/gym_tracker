import 'package:flutter/widgets.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/backend/backend.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/monitoring/monitoring.dart';
import 'package:gym_tracker/core/theme/app_fonts.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/workout/data/workout_sync.dart';

/// Starts monitoring first, then initialises every core service and runs
/// the app. Anything that fails during start-up is reported.
Future<void> bootstrap(Widget Function() builder) async {
  WidgetsFlutterBinding.ensureInitialized();
  AppFonts.registerLicenses();
  await Monitoring.run(() async {
    await Backend.init();
    await Analytics.init();
    await Dependencies.init();
    WorkoutSync(Dependencies.workoutRepository).start();
    await AppUi.initialize();
    return AppUi.wrap(builder());
  });
}
