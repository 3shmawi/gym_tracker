import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_theme.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_draft.dart';
import 'package:gym_tracker/features/workout/domain/services/rest_alarm.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_view.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/rest_alarm_sync.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/rest_on_time_sheet.dart';
import 'package:gym_tracker/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/fake_rest_alarm.dart';

/// The "Rest over" notification, driven from the real workout screen:
/// router, controller, storage and app lifecycle; only the phone's
/// notification center is faked.
void main() {
  final now = DateTime(2026, 11, 2, 18);
  late FakeRestAlarm alarm;
  late LocalWorkoutRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
    await repo.savePlan(PlanTemplates.fiveDaySplit);
    // Legs (day 3): the squat rests 120 s.
    await repo.saveDraft(WorkoutDraft(dayId: 'day-3', startedAt: now));
    alarm = FakeRestAlarm();
    appRouter.go(AppRoutes.workout);
  });

  Future<void> open(WidgetTester tester, {Locale? locale}) async {
    tester.view
      ..physicalSize = const Size(1125, 2436)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          workoutRepositoryProvider.overrideWithValue(repo),
          clockProvider.overrideWithValue(() => now),
          restAlarmProvider.overrideWithValue(alarm),
        ],
        child: AppUi.testWrap(
          AppScreenScale(
            builder: (context) => MaterialApp.router(
              routerConfig: appRouter,
              locale: locale,
              theme: AppTheme.light,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ActiveWorkoutView), findsOneWidget);
  }

  Future<void> log(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('log_set_button')));
    await tester.pumpAndSettle();
  }

  Future<void> lifecycle(WidgetTester tester, AppLifecycleState s) async {
    tester.binding.handleAppLifecycleStateChanged(s);
    await tester.pumpAndSettle();
  }

  testWidgets('first rest asks once; nothing rings while on screen', (
    tester,
  ) async {
    await open(tester);
    expect(alarm.asked, 0, reason: 'never at launch');
    await log(tester);
    expect(alarm.asked, 1);
    expect(alarm.scheduled, isNull);
    await tester.tap(find.byKey(const Key('rest_skip')));
    await tester.pumpAndSettle();
    await log(tester);
    expect(alarm.asked, 2, reason: 'asked again, answered alreadyAsked');
    expect(find.byType(RestOnTimeSheet), findsNothing);
  });

  testWidgets('locked during a rest: "Rest over · squat · set 2" at its end', (
    tester,
  ) async {
    await open(tester);
    await log(tester);
    await lifecycle(tester, AppLifecycleState.inactive);
    await lifecycle(tester, AppLifecycleState.hidden);
    await lifecycle(tester, AppLifecycleState.paused);
    expect(
      alarm.scheduled,
      RestAlarmNotice(
        at: now.add(const Duration(seconds: 120)),
        title: 'Rest over',
        body: 'Barbell Back Squat · set 2',
        channelName: 'Rest timer',
      ),
    );

    // Back on the screen: gone, the countdown is there.
    await lifecycle(tester, AppLifecycleState.hidden);
    await lifecycle(tester, AppLifecycleState.inactive);
    await lifecycle(tester, AppLifecycleState.resumed);
    expect(alarm.scheduled, isNull);
  });

  testWidgets('+15 s moves it, skip removes it', (tester) async {
    await open(tester);
    await log(tester);
    await tester.tap(find.byKey(const Key('rest_add_15')));
    await tester.pumpAndSettle();
    await lifecycle(tester, AppLifecycleState.inactive);
    expect(alarm.scheduled!.at, now.add(const Duration(seconds: 135)));
    await lifecycle(tester, AppLifecycleState.resumed);

    await tester.tap(find.byKey(const Key('rest_skip')));
    await tester.pumpAndSettle();
    await lifecycle(tester, AppLifecycleState.inactive);
    expect(alarm.scheduled, isNull);
  });

  testWidgets('closing the workout removes it', (tester) async {
    await open(tester);
    await log(tester);
    await tester.tap(find.byKey(const Key('workout_close')));
    await tester.pumpAndSettle();
    expect(find.byType(ActiveWorkoutView), findsNothing);
    expect(alarm.calls.last, 'cancel');
    await lifecycle(tester, AppLifecycleState.paused);
    expect(alarm.scheduled, isNull);
  });

  testWidgets('finishing removes it', (tester) async {
    await open(tester);
    await log(tester);
    await tester.tap(find.byKey(const Key('workout_finish_menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('finish_confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(ActiveWorkoutView), findsNothing);
    expect(alarm.scheduled, isNull);
    expect(alarm.calls.last, 'cancel');
  });

  testWidgets('Arabic', (tester) async {
    await open(tester, locale: const Locale('ar'));
    await log(tester);
    await lifecycle(tester, AppLifecycleState.paused);
    expect(alarm.scheduled!.title, 'الراحة خلصت');
    expect(alarm.scheduled!.body, 'بار اسكوات حر · مجموعة 2');
    expect(alarm.scheduled!.channelName, 'مؤقت الراحة');
  });

  group('Android 14+: Alarms & reminders off', () {
    setUp(() => alarm.access = RestAlarmAccess.needsOnTime);

    testWidgets('explains, then opens the settings page', (tester) async {
      await open(tester);
      await log(tester);
      expect(find.text('Ring when your rest is over?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('rest_on_time_open')));
      await tester.pumpAndSettle();
      expect(alarm.openedSettings, 1);
      expect(find.byType(RestOnTimeSheet), findsNothing);
    });

    testWidgets('Not now: nothing opens, never asked again', (tester) async {
      await open(tester);
      await log(tester);
      await tester.tap(find.byKey(const Key('rest_on_time_later')));
      await tester.pumpAndSettle();
      expect(alarm.openedSettings, 0);
      await tester.tap(find.byKey(const Key('rest_skip')));
      await tester.pumpAndSettle();
      await log(tester);
      expect(find.byType(RestOnTimeSheet), findsNothing);
    });
  });

  testWidgets('denied: the workout goes on, no sheet', (tester) async {
    alarm.access = RestAlarmAccess.denied;
    await open(tester);
    await log(tester);
    expect(find.byType(RestOnTimeSheet), findsNothing);
    expect(find.byKey(const Key('rest_countdown')), findsOneWidget);
  });
}
