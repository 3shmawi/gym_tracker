import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/domain/entities/next_workout.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/usecases/get_next_workout.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_view.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';

/// Day 1 after a Day-4 session with the brief's real numbers, finished on
/// Monday and opened on Thursday: the workout waited.
NextWorkout day1Waiting() =>
    const GetNextWorkout()(PlanTemplates.fiveDaySplit, [
      WorkoutSession(
        dayIndex: 4,
        finishedAt: DateTime(2026, 11, 2, 19),
        sets: [
          for (final r in [12, 12, 11])
            LoggedSet(exerciseId: 'flat_db_press', weight: 22.5, reps: r),
          for (var i = 0; i < 3; i++)
            const LoggedSet(
              exerciseId: 'wide_lat_pulldown',
              weight: 50,
              reps: 12,
            ),
          for (final r in [8, 7, 7])
            LoggedSet(exerciseId: 'close_grip_row', weight: 50, reps: r),
        ],
      ),
    ], now: DateTime(2026, 11, 5, 18));

NextWorkout day2() => const GetNextWorkout()(PlanTemplates.fiveDaySplit, [
  WorkoutSession(
    dayIndex: 0,
    finishedAt: DateTime(2026, 11, 2),
    sets: const [],
  ),
], now: DateTime(2026, 11, 3));

Widget view(
  AsyncValue<NextWorkout?> state, {
  VoidCallback? onStart,
  VoidCallback? onRetry,
  VoidCallback? onUseTemplate,
  ValueChanged<int>? onChooseDay,
}) => NextWorkoutView(
  state: state,
  onRetry: onRetry ?? () {},
  onUseTemplate: onUseTemplate ?? () {},
  onOpenSettings: () {},
  onChooseDay: onChooseDay ?? (_) {},
  onStart: onStart,
);

/// Finds text ignoring the LTR isolates around numbers.
Finder textPlain(String text) => find.byWidgetPredicate(
  (w) => w is Text && w.data?.replaceAll(RegExp('[\u2066\u2069]'), '') == text,
);

void main() {
  group(NextWorkoutView, () {
    testWidgets('shows the day, last time and the suggestion', (tester) async {
      await tester.pumpApp(view(AsyncData(day1Waiting()), onStart: () {}));

      expect(find.text('Day 1 of 5'), findsOneWidget);
      expect(find.text('Chest & Back'), findsOneWidget);
      expect(find.text('7 exercises · 21 sets'), findsOneWidget);
      expect(find.text('Wide Lat Pulldown'), findsOneWidget);
      expect(find.text('سحب عالي واسع'), findsOneWidget);
      expect(textPlain('3×12 · Last: 50×12 ×3'), findsOneWidget);
      expect(find.text('52.5 kg'), findsOneWidget);
      expect(find.text('↑ Increase'), findsOneWidget);
      expect(textPlain('3×12 · Last: 22.5×12, 12, 11'), findsOneWidget);
      expect(find.text('→ Keep'), findsOneWidget);
      expect(find.text('↓ Decrease'), findsOneWidget);
      expect(find.text('First time'), findsWidgets);
    });

    testWidgets('says the workout waited after a missed day', (tester) async {
      await tester.pumpApp(view(AsyncData(day1Waiting())));
      expect(find.textContaining('waiting since Tuesday'), findsOneWidget);
    });

    testWidgets('no banner when nothing was missed', (tester) async {
      await tester.pumpApp(view(AsyncData(day2())));
      expect(find.textContaining('waiting since'), findsNothing);
    });

    testWidgets('marks supersets (day 2)', (tester) async {
      await tester.pumpApp(view(AsyncData(day2())));
      expect(find.text('Superset with the next exercise'), findsNWidgets(2));
      expect(find.byIcon(Icons.swap_vert), findsNWidgets(2));
    });

    testWidgets('Start appears only when available and calls back', (
      tester,
    ) async {
      await tester.pumpApp(view(AsyncData(day2())));
      expect(find.text('Start workout'), findsNothing);

      var started = 0;
      await tester.pumpApp(view(AsyncData(day2()), onStart: () => started++));
      await tester.tap(find.text('Start workout'));
      expect(started, 1);
    });

    testWidgets('change day: pick legs for tomorrow', (tester) async {
      int? chosen;
      await tester.pumpApp(
        view(AsyncData(day2()), onChooseDay: (d) => chosen = d),
      );
      await tester.tap(find.byKey(const Key('change_day_button')));
      await tester.pumpAndSettle();
      expect(find.text('Which workout is next?'), findsOneWidget);
      expect(find.text('Day 3'), findsOneWidget);
      expect(find.text('Legs'), findsOneWidget);

      await tester.tap(find.byKey(const Key('choose_day_2')));
      await tester.pumpAndSettle();
      expect(chosen, 2);
      expect(find.text('Which workout is next?'), findsNothing);
    });

    testWidgets('picking the current day changes nothing', (tester) async {
      int? chosen;
      await tester.pumpApp(
        view(AsyncData(day2()), onChooseDay: (d) => chosen = d),
      );
      await tester.tap(find.byKey(const Key('change_day_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('choose_day_1')));
      await tester.pumpAndSettle();
      expect(chosen, isNull);
    });

    testWidgets('no plan: offers the 5-day template', (tester) async {
      var used = 0;
      await tester.pumpApp(
        view(const AsyncData(null), onUseTemplate: () => used++),
      );
      await tester.tap(find.text('Start with the 5-day plan'));
      expect(used, 1);
    });

    testWidgets('error: friendly message and retry', (tester) async {
      var retried = 0;
      await tester.pumpApp(
        view(
          const AsyncError(NetworkFailure(), StackTrace.empty),
          onRetry: () => retried++,
        ),
      );
      expect(find.text(l10nEn.errorNetwork), findsOneWidget);
      await tester.tap(find.text(l10nEn.retry));
      expect(retried, 1);
    });

    testWidgets('an unexpected error never shows its details', (tester) async {
      await tester.pumpApp(
        view(AsyncError(StateError('secret path'), StackTrace.empty)),
      );
      expect(find.textContaining('secret'), findsNothing);
      expect(find.text(l10nEn.errorUnknown), findsOneWidget);
    });

    testWidgets('loading shows a spinner', (tester) async {
      await tester.pumpApp(view(const AsyncLoading()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('Arabic shows Arabic names first', (tester) async {
      await tester.pumpApp(
        view(AsyncData(day1Waiting())),
        locale: const Locale('ar'),
      );
      expect(find.text('بنش وضهر'), findsOneWidget);
      expect(find.text('اليوم 1 من 5'), findsOneWidget);
      expect(find.text('52.5 كجم'), findsOneWidget);
      expect(find.text('↑ زوّد'), findsOneWidget);
      // Numbers stay in reading order inside Arabic text.
      expect(
        find.text('\u20663×12\u2069 · آخر مرة: \u206622.5×12, 12, 11\u2069'),
        findsOneWidget,
      );
    });
  });

  screensUiTests({
    'next_workout': () => view(AsyncData(day1Waiting()), onStart: () {}),
    'next_workout_supersets': () => view(AsyncData(day2())),
    'next_workout_no_plan': () => view(const AsyncData(null)),
    'next_workout_error': () =>
        view(const AsyncError(NetworkFailure(), StackTrace.empty)),
  });
}
