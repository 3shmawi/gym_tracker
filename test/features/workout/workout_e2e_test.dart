import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_theme.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_view.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The leg-day flow from integration_test/app_test.dart, on the real
/// router, controllers and on-phone storage, without a device.
void main() {
  late SharedPreferences prefs;
  var now = DateTime(2026, 11, 2, 18);

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
          clockProvider.overrideWithValue(() => now),
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
    now = DateTime(2026, 11, 2, 18);
    appRouter.go(AppRoutes.home);
  });

  testWidgets('leg day: pick day 3, log, rest, finish, plan advances', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('use_template_button')));
    await tester.pumpAndSettle();
    expect(find.text('Day 1 of 5'), findsOneWidget);

    await tester.tap(find.byKey(const Key('change_day_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choose_day_2')));
    await tester.pumpAndSettle();
    expect(find.text('Day 3 of 5'), findsOneWidget);
    expect(find.text('Legs'), findsOneWidget);

    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
    expect(find.byType(ActiveWorkoutView), findsOneWidget);
    expect(find.text('Barbell Back Squat'), findsOneWidget);
    expect(find.text('Set 1 of 3'), findsOneWidget);

    for (var i = 0; i < 4; i++) {
      await tester.tap(find.bySemanticsLabel('Add 5 kg'));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('log_set_button')));
    await tester.pumpAndSettle();
    expect(find.text('2:00'), findsOneWidget, reason: 'squat rests 120 s');

    await tester.tap(find.byKey(const Key('rest_add_15')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('2:15'), findsOneWidget);
    await tester.tap(find.byKey(const Key('rest_skip')));
    await tester.pumpAndSettle();

    expect(find.text('Set 2 of 3'), findsOneWidget);
    expect(find.text('Log \u206620 × 12\u2069'), findsOneWidget);
    await tester.tap(find.byKey(const Key('log_set_button')));
    await tester.pumpAndSettle();

    // Leave and come back: the workout is still there.
    await tester.tap(find.byKey(const Key('workout_close')));
    await tester.pumpAndSettle();
    expect(find.text('Day 3 of 5'), findsOneWidget);
    // Home says what its button does now, and has no floating pill.
    expect(find.text('Start workout'), findsNothing);
    expect(find.byKey(const Key('workout_pill')), findsNothing);
    await tester.tap(find.text('Continue workout'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('set_chip_barbell_squat_2')), findsOneWidget);

    now = now.add(const Duration(minutes: 40));
    await tester.tap(find.byKey(const Key('workout_finish_menu')));
    await tester.pumpAndSettle();
    expect(find.text('22 sets left'), findsOneWidget);
    await tester.tap(find.byKey(const Key('finish_confirm')));
    await tester.pumpAndSettle();

    expect(find.byType(ActiveWorkoutView), findsNothing);
    expect(find.text('Day 4 of 5'), findsOneWidget);
    expect(find.textContaining('waiting since'), findsNothing);
  });

  testWidgets('next time, the squat suggestion comes from this workout', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('use_template_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('change_day_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choose_day_2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();

    // 60 kg × 12 for all 3 sets → next time 65 kg ↑.
    for (var i = 0; i < 12; i++) {
      await tester.tap(find.bySemanticsLabel('Add 5 kg'));
      await tester.pump();
    }
    for (var set = 0; set < 3; set++) {
      await tester.tap(find.byKey(const Key('log_set_button')));
      await tester.pumpAndSettle();
      if (set < 2) {
        await tester.tap(find.byKey(const Key('rest_skip')));
        await tester.pumpAndSettle();
      }
    }
    await tester.tap(find.byKey(const Key('workout_finish_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish_confirm')));
    await tester.pumpAndSettle();

    // Pick legs again: the squat shows 65 kg ↑.
    await tester.tap(find.byKey(const Key('change_day_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choose_day_2')));
    await tester.pumpAndSettle();
    expect(find.text('65 kg'), findsOneWidget);
    expect(find.text('↑ Increase'), findsOneWidget);
  });
}
