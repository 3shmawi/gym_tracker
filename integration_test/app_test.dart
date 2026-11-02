import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/feature_flags/feature_flags.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/splash/animated_splash.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/gym/presentation/join_page.dart';
import 'package:gym_tracker/features/settings/presentation/settings_view.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/services/rest_alarm.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_view.dart';
import 'package:gym_tracker/features/workout/presentation/exercise_history_view.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_page.dart';
import 'package:gym_tracker/features/workout/presentation/progress_view.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/exercise_preview_row.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/level_card.dart';
import 'package:gym_tracker/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/helpers/fake_rest_alarm.dart';
import 'flows/build_plan_flow.dart';
import 'helpers/demo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first launch: pick the 5-day plan and see the next workout', (
    tester,
  ) async {
    // A fresh install: no plan, no history.
    await freshInstall(tester);

    // The animated splash opens the demo: the first launch of the day plays
    // the full logo animation while start-up runs, then hands off.
    final started = app.main();
    await tester.pump();
    expect(find.byType(AnimatedSplash), findsOneWidget);
    expect(find.byType(AzmLogoAnimation), findsOneWidget);
    await started;
    useFakeRestAlarm();
    await tester.pumpAndSettle();
    expect(find.byType(AzmLogoAnimation), findsNothing);
    await beat(tester, 1500);

    expect(find.byType(NextWorkoutPage), findsOneWidget);
    await tester.tap(find.byKey(const Key('use_template_button')));
    await tester.pumpAndSettle();
    await beat(tester, 1500);

    // Day 1 of 5, Chest & Back, all seven exercises, first time for each.
    expect(find.byType(ExercisePreviewRow), findsWidgets);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    await beat(tester, 1200);
    await tester.drag(find.byType(ListView), const Offset(0, 400));
    await tester.pumpAndSettle();
    await beat(tester);

    await tester.tap(find.byKey(const Key('home_settings_button')));
    await tester.pumpAndSettle();
    await beat(tester);
    expect(find.byType(SettingsView), findsOneWidget);
    await beat(tester, 1500);
  });

  testWidgets('build your plan: two exercises, a target, start', (
    tester,
  ) async {
    await freshInstall(tester);
    await app.main();
    await tester.pumpAndSettle();
    await beat(tester, 1500);

    await buildPlanFlow(tester);
    expect(find.byType(ActiveWorkoutView), findsOneWidget);
    await beat(tester, 2000);
  });

  testWidgets('leg day: pick day 3, log sets, rest, finish', (tester) async {
    await freshInstall(tester);
    await app.main();
    useFakeRestAlarm();
    await tester.pumpAndSettle();
    await beat(tester);

    await tester.tap(find.byKey(const Key('use_template_button')));
    await tester.pumpAndSettle();
    await beat(tester);

    // Tomorrow is legs: choose day 3.
    await tester.tap(find.byKey(const Key('change_day_button')).hitTestable());
    await tester.pumpAndSettle();
    await beat(tester);
    await tester.tap(find.byKey(const Key('choose_day_2')).hitTestable());
    await tester.pumpAndSettle();
    await beat(tester, 1200);

    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
    expect(find.byType(ActiveWorkoutView), findsOneWidget);
    await beat(tester);

    // Squat set 1: add 20 kg (4 × 5 kg), one tap to log.
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.bySemanticsLabel('Add 5 kg'));
      await tester.pump(const Duration(milliseconds: 250));
    }
    await beat(tester);
    await tester.tap(find.byKey(const Key('log_set_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rest_countdown')), findsOneWidget);
    await beat(tester, 2000);

    await tester.tap(find.byKey(const Key('rest_add_15')));
    await tester.pump();
    await beat(tester);
    await tester.tap(find.byKey(const Key('rest_skip')));
    await tester.pumpAndSettle();
    await beat(tester);

    // Set 2 is prefilled with set 1's weight: one tap.
    await tester.tap(find.byKey(const Key('log_set_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rest_skip')));
    await tester.pumpAndSettle();
    await beat(tester);

    await tester.tap(find.byKey(const Key('workout_finish_menu')));
    await tester.pumpAndSettle();
    await beat(tester, 1500);
    await tester.tap(find.byKey(const Key('finish_confirm')));
    await tester.pumpAndSettle();
    await beat(tester);

    // Back home: the plan moved on to day 4.
    expect(find.text('Day 4 of 5'), findsOneWidget);
    await beat(tester, 1500);

    // Progress: the squat now has today's two sets.
    await tester.tap(find.byKey(const Key('home_progress_button')));
    await tester.pumpAndSettle();
    expect(find.byType(ProgressView), findsOneWidget);
    await beat(tester);
    // Home is still mounted under Progress: scroll Progress's own list.
    final squat = find.byKey(const Key('progress_barbell_squat'));
    await tester.scrollUntilVisible(
      squat,
      200,
      scrollable: find
          .descendant(
            of: find.byType(ProgressView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await beat(tester);
    await tester.tap(squat.hitTestable());
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseHistoryView), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    await beat(tester, 2000);
  });

  testWidgets('a month of training: the home screen shows Intermediate', (
    tester,
  ) async {
    await freshInstall(tester);
    // Four weeks in a row with three workouts each, the last one a week ago.
    final repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
    await repo.savePlan(PlanTemplates.fiveDaySplit);
    // Weeks run Saturday → Friday: train Sat, Sun and Mon of each week.
    final today = DateTime.now();
    final saturday = DateTime(
      today.year,
      today.month,
      today.day - (today.weekday - DateTime.saturday) % 7,
      18,
    );
    for (var week = 4; week >= 1; week--) {
      for (var d = 0; d < 3; d++) {
        await repo.saveSession(
          WorkoutSession(
            dayId: legacyDayId(d),
            finishedAt: DateTime(
              saturday.year,
              saturday.month,
              saturday.day - week * 7 + d,
              18,
            ),
            sets: const [],
          ),
        );
      }
    }

    await app.main();
    useFakeRestAlarm();
    await tester.pumpAndSettle();
    await beat(tester);

    // The level card sits under today's exercises.
    await tester.scrollUntilVisible(
      find.byType(LevelCard),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(AzmLevelFigure), findsOneWidget);
    expect(
      tester.widget<AzmLevelFigure>(find.byType(AzmLevelFigure)).figure,
      LevelFigure.intermediate,
    );
    expect(find.text('Your level · Intermediate'), findsOneWidget);
    await beat(tester, 2000);
  });
  testWidgets('rest notification: lock the phone during a rest', (
    tester,
  ) async {
    await freshInstall(tester);
    await app.main();
    final alarm = useFakeRestAlarm();
    await tester.pumpAndSettle();
    await beat(tester);

    await tester.tap(find.byKey(const Key('use_template_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('change_day_button')).hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('choose_day_2')).hitTestable());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start workout'));
    await tester.pumpAndSettle();
    await beat(tester);

    // Never asked at launch: the question comes with the first rest.
    expect(alarm.asked, 0);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.bySemanticsLabel('Add 5 kg'));
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.tap(find.byKey(const Key('log_set_button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rest_countdown')), findsOneWidget);
    expect(alarm.asked, 1);
    expect(alarm.scheduled, isNull, reason: 'on screen: the timer rings');
    await beat(tester, 1500);

    // Lock the phone: "Rest over · Barbell Back Squat · set 2" waits for
    // the end of the 2-minute rest.
    final before = DateTime.now();
    await lockPhone(tester);
    final notice = alarm.scheduled!;
    expect(notice.title, 'Rest over');
    expect(notice.body, 'Barbell Back Squat · set 2');
    expect(notice.at.difference(before).inSeconds, inInclusiveRange(100, 120));

    // Unlock: the countdown is back and the notification is gone.
    await unlockPhone(tester);
    expect(alarm.scheduled, isNull);
    await beat(tester);

    // +15 s moves it.
    await tester.tap(find.byKey(const Key('rest_add_15')));
    await tester.pumpAndSettle();
    await lockPhone(tester);
    expect(alarm.scheduled!.at, notice.at.add(const Duration(seconds: 15)));
    await unlockPhone(tester);

    // Skip: nothing left to ring.
    await tester.tap(find.byKey(const Key('rest_skip')));
    await tester.pumpAndSettle();
    await lockPhone(tester);
    expect(alarm.scheduled, isNull);
    await unlockPhone(tester);
    await beat(tester);

    // Log set 2, then close the workout mid-rest: nothing rings later.
    await tester.tap(find.byKey(const Key('log_set_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workout_close')));
    await tester.pumpAndSettle();
    await lockPhone(tester);
    expect(alarm.scheduled, isNull);
    await unlockPhone(tester);
    await beat(tester, 1500);
  });

  testWidgets('an invite link fills in the code and waits for the tap', (
    tester,
  ) async {
    // Behind the gym_join flag: off in the stores until joining works.
    FeatureFlags.overrides[Flags.gymJoin] = true;
    addTearDown(FeatureFlags.overrides.clear);
    await freshInstall(tester);
    await app.main();
    useFakeRestAlarm();
    await tester.pumpAndSettle();
    await beat(tester, 1200);

    // Someone scans the QR (or taps the link) while the app is installed.
    appRouter.go('/join/k7m2qx');
    await tester.pumpAndSettle();
    expect(find.byType(JoinPage), findsOneWidget);
    expect(find.text('K'), findsOneWidget);
    expect(find.text('X'), findsOneWidget);
    await beat(tester, 1500);

    // The link only filled the boxes in: nothing joined. Join is the
    // member's own tap (and, until joining ships, stays off).
    expect(find.byKey(const Key('join_not_ready')), findsOneWidget);
    await beat(tester, 1200);

    // A bad link shows an empty field and says why.
    appRouter.go('/join/not-a-code');
    await tester.pumpAndSettle();
    expect(find.byType(JoinPage), findsOneWidget);
    await beat(tester, 1500);

    // The member can still type the code by hand.
    await tester.enterText(
      find.descendant(
        of: find.byKey(const Key('join_code')),
        matching: find.byType(TextField),
      ),
      'hjk2mn',
    );
    await tester.pumpAndSettle();
    expect(find.text('H'), findsOneWidget);
    await beat(tester, 1500);
  });
}

/// A fresh install for each test: unmount the previous test's app (runApp
/// with the same root widget would keep its state, e.g. the ProviderScope),
/// send the app-wide router back home and clear everything saved on the
/// device.
Future<void> freshInstall(WidgetTester tester) async {
  // Pop back home while the previous app is still mounted, so no page of
  // it (e.g. Settings) is left in the router to cover the new one.
  appRouter.go(AppRoutes.home);
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  await (await SharedPreferences.getInstance()).clear();
}

/// The phone's notification center can't be driven from a test (and iOS
/// would stop on its permission prompt), so the app's [RestAlarm] is
/// swapped after start-up; what it receives is checked instead.
FakeRestAlarm useFakeRestAlarm() {
  final alarm = FakeRestAlarm();
  Dependencies.restAlarm = alarm;
  return alarm;
}

/// What iOS reports when the side button is pressed, and back.
Future<void> lockPhone(WidgetTester tester) async {
  [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
  ].forEach(tester.binding.handleAppLifecycleStateChanged);
  await tester.pumpAndSettle();
}

Future<void> unlockPhone(WidgetTester tester) async {
  [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ].forEach(tester.binding.handleAppLifecycleStateChanged);
  await tester.pumpAndSettle();
}
