import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/feature_flags/feature_flags.dart';
import 'package:gym_tracker/core/legal/legal.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/splash/animated_splash.dart';
import 'package:gym_tracker/core/theme/app_colors.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/brand_color_rule.dart';
import 'package:gym_tracker/core/theme/brand_colors.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/gym/presentation/join_page.dart';
import 'package:gym_tracker/features/gym/presentation/joined_view.dart';
import 'package:gym_tracker/features/gym/presentation/scanner_camera.dart';
import 'package:gym_tracker/features/gym/presentation/scanner_view.dart';
import 'package:gym_tracker/features/gym/presentation/welcome_view.dart';
import 'package:gym_tracker/features/library/presentation/exercise_guide_view.dart';
import 'package:gym_tracker/features/library/presentation/widgets/exercise_thumb.dart';
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
import '../test/helpers/gym_app.dart' show FakeCamera;
import '../test/helpers/gym_fakes.dart';
import '../test/helpers/plan_sync_fakes.dart';
import 'flows/build_plan_flow.dart';
import 'flows/gym_pictures_flow.dart';
import 'helpers/demo.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('first launch: pick the 5-day plan and see the next workout', (
    tester,
  ) async {
    // A fresh install: no plan, no history, nothing agreed yet.
    await freshInstall(tester, agreed: false);

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

    // Once, before anything: the Terms and Privacy Policy.
    expect(find.byKey(const Key('consent_agree')), findsOneWidget);
    await tester.tap(find.byKey(const Key('consent_agree')));
    await tester.pumpAndSettle();
    await beat(tester);

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

    await tester.tap(find.byKey(const Key('home_start_button')));
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
    await tester.tap(find.byKey(const Key('home_start_button')));
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

    // Log set 2, then close the workout mid-rest: the pill keeps the rest,
    // so locking the phone on the home screen still schedules it.
    await tester.tap(find.byKey(const Key('log_set_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workout_close')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('workout_pill')), findsOneWidget);
    await lockPhone(tester);
    expect(alarm.scheduled?.body, 'Barbell Back Squat · set 3');
    await unlockPhone(tester);
    expect(alarm.scheduled, isNull);

    // Finishing the workout from the pill's screen removes it for good.
    await tester.tap(find.byKey(const Key('workout_pill')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workout_finish_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish_confirm')));
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
    // member's own tap.
    expect(find.byKey(const Key('join_submit')), findsOneWidget);
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

  testWidgets('join a gym: scan the QR, "Welcome", then today\'s workout', (
    tester,
  ) async {
    // The simulator has no camera and the demo no server: a fake camera and a
    // gym that accepts the code, set after start-up.
    FeatureFlags.overrides[Flags.gymJoin] = true;
    addTearDown(FeatureFlags.overrides.clear);
    await freshInstall(tester);
    await app.main();
    useFakeRestAlarm();
    final camera = FakeCamera();
    scannerCameraOverride = camera.builder;
    addTearDown(() => scannerCameraOverride = null);
    final gyms = FakeGymRepository(redeemResult: Success(joinedGym()));
    Dependencies.gymRepository = gyms;
    final account = FakeAccountRepository();
    Dependencies.accountRepository = account;
    await tester.pumpAndSettle();
    await beat(tester, 1200);

    // A new install asks once how to start.
    expect(find.byType(WelcomeView), findsOneWidget);
    await beat(tester, 1500);
    await tester.tap(find.byKey(const Key('welcome_join')));
    await tester.pumpAndSettle();
    expect(find.byType(ScannerView), findsOneWidget);
    await beat(tester, 1800);

    // The camera reads the QR the captain printed: it joins at once.
    camera.scan('https://azmm.pages.dev/join/K7M2QX');
    await tester.pumpAndSettle();
    // Redeeming signs the phone in (anonymously) first.
    account.emit(anonymousSession);
    await tester.pumpAndSettle();
    expect(gyms.redeemed, [testCode]);
    expect(find.byType(JoinedView), findsOneWidget);
    expect(find.text('Welcome to Iron House'), findsOneWidget);
    await beat(tester, 2500);

    // Start training: today's workout.
    await tester.tap(find.byKey(const Key('joined_start')));
    await tester.pumpAndSettle();
    await beat(tester, 1200);
    expect(find.byType(NextWorkoutPage), findsOneWidget);
    await tester.tap(find.byKey(const Key('use_template_button')));
    await tester.pumpAndSettle();
    expect(find.byType(ExercisePreviewRow), findsWidgets);
    await beat(tester, 2000);
  });

  testWidgets("a gym with its own colour: join, and the app is the gym's", (
    tester,
  ) async {
    // Iron House's owner picked yellow in the dashboard.
    const yellow = '#facc15';
    FeatureFlags.overrides[Flags.gymJoin] = true;
    FeatureFlags.overrides[Flags.gymBrandColours] = true;
    addTearDown(FeatureFlags.overrides.clear);
    await freshInstall(tester);
    await app.main();
    useFakeRestAlarm();
    final camera = FakeCamera();
    scannerCameraOverride = camera.builder;
    addTearDown(() => scannerCameraOverride = null);
    Dependencies.gymRepository = FakeGymRepository(
      redeemResult: Success(joinedGym(color: yellow)),
      memberships: Success([member(color: yellow)]),
    );
    final account = FakeAccountRepository();
    Dependencies.accountRepository = account;
    await tester.pumpAndSettle();
    await beat(tester, 1200);

    Color brandAt(Finder screen) =>
        Theme.of(tester.element(screen)).extension<AppPalette>()!.brand;

    // Before joining: Azm's green.
    expect(find.byType(WelcomeView), findsOneWidget);
    expect(brandAt(find.byType(WelcomeView)), AppColors.primary);
    await beat(tester, 1500);
    await tester.tap(find.byKey(const Key('welcome_join')));
    await tester.pumpAndSettle();
    await beat(tester, 1500);

    // Scan the gym's QR: the welcome is already in the gym's colour.
    camera.scan('https://azmm.pages.dev/join/K7M2QX');
    await tester.pumpAndSettle();
    account.emit(anonymousSession);
    await tester.pumpAndSettle();
    expect(find.text('Welcome to Iron House'), findsOneWidget);
    await beat(tester, 2500);

    // Start training: every button, bar and ring is the gym's yellow.
    await tester.tap(find.byKey(const Key('joined_start')));
    await tester.pumpAndSettle();
    expect(find.byType(NextWorkoutPage), findsOneWidget);
    final gymBrand = brandAt(find.byType(NextWorkoutPage));
    expect(gymBrand, isNot(AppColors.primary));
    expect(
      BrandColorRule.passes(
        BrandColors.toRgb(gymBrand),
        BrandColors.toRgb(
          Theme.of(tester.element(find.byType(NextWorkoutPage)))
              .colorScheme
              .surface,
        ),
        3,
        1,
      ),
      isTrue,
    );
    await beat(tester, 2500);
  });

  testWidgets('in a gym: the captain changes the plan and the app says so', (
    tester,
  ) async {
    FeatureFlags.overrides[Flags.gymJoin] = true;
    addTearDown(FeatureFlags.overrides.clear);
    await freshInstall(tester);
    await app.main();
    useFakeRestAlarm();
    final camera = FakeCamera();
    scannerCameraOverride = camera.builder;
    addTearDown(() => scannerCameraOverride = null);
    Dependencies.gymRepository = FakeGymRepository(
      redeemResult: Success(joinedGym()),
      // The server knows the membership: without it the app's refresh
      // finds none and (rightly) moves the person back to solo, so home
      // showed the solo template instead of the captain's plan.
      memberships: Success([member()]),
    );
    final account = FakeAccountRepository();
    Dependencies.accountRepository = account;
    // The gym's server: the captain's plan, version 1.
    final server = FakePlanServer()..plan = gymPlan(updatedBy: 'captain-m');
    Dependencies.gymPlanRepository = server;
    Dependencies.gymPlanStore = MemoryPlanStore();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('welcome_join')));
    await tester.pumpAndSettle();
    camera.scan('https://azmm.pages.dev/join/K7M2QX');
    await tester.pumpAndSettle();
    account.emit(anonymousSession);
    await tester.pumpAndSettle();
    await beat(tester, 1800);
    await tester.tap(find.byKey(const Key('joined_start')));
    await tester.pumpAndSettle();

    // Today shows the captain's plan: no template to pick.
    expect(find.byType(NextWorkoutPage), findsOneWidget);
    expect(find.byKey(const Key('use_template_button')), findsNothing);
    await beat(tester, 2000);

    // The captain renames a day; the app notices when it comes back.
    server.plan = gymPlan(
      version: 2,
      updatedBy: 'captain-m',
      plan: renamedDay1(),
    );
    await lockPhone(tester);
    await unlockPhone(tester);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Your captain updated your plan'), findsOneWidget);
    await beat(tester, 2500);
    // It goes away by itself.
    await tester.pump(const Duration(seconds: 7));
    expect(find.text('Your captain updated your plan'), findsNothing);
  });

  // Was nested inside unlockPhone (a merge in #38), so it was declared while
  // another test ran ("Can't call test() once tests have begun running")
  // and never ran on its own.
  testWidgets("the gym's pictures: frames, swipe, offline from the cache", (
    tester,
  ) async {
    await gymPicturesFlow(tester);
  });
}

/// A fresh install for each test: unmount the previous test's app (runApp
/// with the same root widget would keep its state, e.g. the ProviderScope),
/// send the app-wide router back home and clear everything saved on the
/// device.
/// [agreed]: the Terms and Privacy Policy were accepted (every test but
/// the first-launch one, which shows that screen).
Future<void> freshInstall(WidgetTester tester, {bool agreed = true}) async {
  // In front again: a test that failed while the phone was "locked" would
  // leave the app paused, and with frames off every pump of the next test
  // waits forever (see lockPhone).
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  // Pop back home while the previous app is still mounted, so no page of
  // it (e.g. Settings) is left in the router to cover the new one.
  appRouter.go(AppRoutes.home);
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  if (agreed) {
    await prefs.setString(PrefsConsentStore.key, ConsentStore.current);
  }
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
  // No pump here: while hidden or paused the engine draws no frames
  // (SchedulerBinding.framesEnabled is false), and on a device a pump waits
  // for a frame, so it never returned and CI hit its 75-minute limit. The
  // app reacts to the lifecycle without a frame (RestAlarmSync); give its
  // futures real time to run instead.
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
}

Future<void> unlockPhone(WidgetTester tester) async {
  [
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ].forEach(tester.binding.handleAppLifecycleStateChanged);
  await tester.pumpAndSettle();

  testWidgets('workout pill: pictures, start from settings, how-to, resume', (
    tester,
  ) async {
    await freshInstall(tester);
    await app.main();
    useFakeRestAlarm();
    await tester.pumpAndSettle();
    await beat(tester);

    await tester.tap(find.byKey(const Key('use_template_button')));
    await tester.pumpAndSettle();
    await beat(tester, 1500);

    // Every exercise of the day shows its picture.
    expect(find.byType(NumberedExerciseThumb), findsWidgets);

    // Settings: the floating pill waits in the corner.
    await tester.tap(find.byKey(const Key('home_settings_button')));
    await tester.pumpAndSettle();
    await beat(tester, 1200);
    expect(find.byType(SettingsView), findsOneWidget);
    expect(find.byKey(const Key('workout_pill')), findsOneWidget);

    // One tap starts day 1 from here.
    await tester.tap(find.byKey(const Key('workout_pill')));
    await tester.pumpAndSettle();
    await beat(tester, 1200);
    expect(find.byType(ActiveWorkoutView), findsOneWidget);
    expect(find.byKey(const Key('workout_pill')), findsNothing);

    // How to do the current exercise: pictures and steps.
    await tester.tap(find.byKey(const Key('how_to_current_flat_db_press')));
    await tester.pumpAndSettle();
    await beat(tester, 1800);
    expect(find.byType(ExerciseGuideView), findsOneWidget);
    expect(find.text('Resume workout'), findsOneWidget);

    // The pill goes back to the same set.
    await tester.tap(find.byKey(const Key('workout_pill')));
    await tester.pumpAndSettle();
    await beat(tester);
    expect(find.byType(ActiveWorkoutView), findsOneWidget);
    expect(find.byType(ExerciseGuideView), findsNothing);
    await tester.tap(find.byKey(const Key('log_set_button')));
    await tester.pumpAndSettle();
    await beat(tester, 1500);
  });
}
