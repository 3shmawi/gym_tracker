import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/presentation/workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/workout_page.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/workout_fakes.dart';

void main() {
  Future<FakeWorkoutRepository> pump(
    WidgetTester tester, {
    FakeWorkoutRepository? repo,
    Locale locale = const Locale('en'),
  }) async {
    final fake = repo ?? FakeWorkoutRepository(plan: testPlan);
    await tester.pumpApp(
      ProviderScope(
        overrides: [workoutRepositoryProvider.overrideWithValue(fake)],
        child: const WorkoutPage(),
      ),
      locale: locale,
    );
    await tester.pumpAndSettle();
    return fake;
  }

  testWidgets('shows the next day and a start button', (tester) async {
    await pump(tester);

    expect(find.text('Chest & Back'), findsOneWidget);
    expect(find.text(l10nEn.workoutDayOf(1, 2)), findsOneWidget);
    expect(find.byKey(const Key('workout_start_button')), findsOneWidget);
    expect(find.text(l10nEn.workoutFirstTime), findsNWidgets(2));
    expect(find.byKey(const Key('home_settings_button')), findsOneWidget);
  });

  testWidgets('log a set with one tap, then finish the workout', (
    tester,
  ) async {
    final repo = await pump(tester);

    await tester.tap(find.byKey(const Key('workout_start_button')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('log_set_bench')));
    await tester.pumpAndSettle();
    expect(repo.sets.single.reps, 10, reason: 'prefilled with target reps');
    expect(find.text(l10nEn.workoutLogSet(2)), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const Key('workout_complete_button')),
      200,
    );
    await tester.tap(find.byKey(const Key('workout_complete_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workout_complete_confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Legs'), findsOneWidget);
    expect(find.text(l10nEn.workoutCompleted('Legs')), findsOneWidget);
  });

  testWidgets('steppers change the weight before logging', (tester) async {
    final repo = await pump(tester);
    await tester.tap(find.byKey(const Key('workout_start_button')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byTooltip(l10nEn.workoutIncrease(l10nEn.workoutWeight)).first,
    );
    await tester.tap(
      find.byTooltip(l10nEn.workoutIncrease(l10nEn.workoutWeight)).first,
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('log_set_bench')));
    await tester.pumpAndSettle();

    expect(repo.sets.single.weightKg, 5);
  });

  testWidgets('no plan shows the empty state', (tester) async {
    await pump(tester, repo: FakeWorkoutRepository());
    expect(find.text(l10nEn.workoutNoPlan), findsOneWidget);
  });

  testWidgets('first launch offline shows an error with retry', (tester) async {
    await pump(
      tester,
      repo: FakeWorkoutRepository(
        refreshResult: const Failed(NetworkFailure()),
      ),
    );
    expect(find.text(l10nEn.errorNetwork), findsOneWidget);
    expect(find.text(l10nEn.retry), findsOneWidget);
  });

  testWidgets('meets accessibility guidelines during a workout', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('workout_start_button')));
    await tester.pumpAndSettle();
    await tester.expectAccessible();
  });

  testWidgets('Arabic: names in Arabic, right to left', (tester) async {
    await pump(tester, locale: const Locale('ar'));

    expect(find.text('بنش وضهر'), findsOneWidget);
    final direction = Directionality.of(tester.element(find.text('بنش وضهر')));
    expect(direction, TextDirection.rtl);
  });
}
