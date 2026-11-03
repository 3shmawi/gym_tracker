import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/presentation/plan_editor_controller.dart';
import 'package:gym_tracker/features/workout/presentation/plan_exercise_view.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';
import 'plan_samples.dart';

class ExerciseCalls {
  final targets = <Map<String, Object>>[];
  final renamed = <LocalizedName>[];
  final supersets = <bool>[];
  int deletes = 0;
  int backs = 0;
  int retries = 0;
  int saveRetries = 0;
}

Widget view(
  AsyncValue<PlanEditorState> state, {
  String dayId = 'day-2',
  String exerciseId = 'db_front_raise',
  ExerciseCalls? calls,
}) {
  final c = calls ?? ExerciseCalls();
  return PlanExerciseView(
    state: state,
    dayId: dayId,
    exerciseId: exerciseId,
    onRetry: () => c.retries++,
    onRetrySave: () => c.saveRetries++,
    onBackToPlan: () => c.backs++,
    onRename: c.renamed.add,
    onSetTargets: ({sets, reps, restSeconds, weightStep}) => c.targets.add({
      'sets': ?sets,
      'reps': ?reps,
      'rest': ?restSeconds,
      'step': ?weightStep,
    }),
    onSetSuperset: c.supersets.add,
    onDelete: () => c.deletes++,
  );
}

Future<void> tapKey(WidgetTester tester, Key key) async {
  await tester.ensureVisible(find.byKey(key));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(key));
  await tester.pumpAndSettle();
}

Finder inRow(String rowKey, String label) => find.descendant(
  of: find.byKey(Key(rowKey)),
  matching: find.bySemanticsLabel(label),
);

void main() {
  group('PlanExerciseView', () {
    testWidgets('targets only: steppers work, rename/delete/superset do not', (
      tester,
    ) async {
      final calls = ExerciseCalls();
      await tester.pumpApp(
        view(
          const AsyncData(targetsOnlyState),
          dayId: 'day-1',
          exerciseId: 'flat_db_press',
          calls: calls,
        ),
      );
      expect(find.byKey(const Key('plan_rename_exercise')), findsNothing);
      expect(find.byKey(const Key('plan_delete_exercise')), findsNothing);
      await tester.tap(find.bySemanticsLabel(l10nEn.planSetsMore));
      expect(calls.targets, hasLength(1));
    });

    testWidgets('read-only: every stepper is off', (tester) async {
      final calls = ExerciseCalls();
      await tester.pumpApp(
        view(
          const AsyncData(captainOnlyState),
          dayId: 'day-1',
          exerciseId: 'flat_db_press',
          calls: calls,
        ),
      );
      await tester.tap(
        find.bySemanticsLabel(l10nEn.planSetsMore),
        warnIfMissed: false,
      );
      expect(calls.targets, isEmpty);
      expect(find.byKey(const Key('plan_managed_banner')), findsOneWidget);
    });

    testWidgets('names and every target', (tester) async {
      await tester.pumpApp(view(const AsyncData(planState)));
      expect(find.text('Exercise'), findsOneWidget);
      expect(find.text('Dumbbell Front Raise'), findsOneWidget);
      expect(find.text('رفرفة دمبل أمامي كتف'), findsOneWidget);
      expect(find.text('Sets'), findsOneWidget);
      expect(find.text('Reps'), findsOneWidget);
      expect(find.text('Rest'), findsOneWidget);
      expect(find.text('Weight step'), findsOneWidget);
      expect(find.byKey(const Key('plan_step_2.5')), findsOneWidget);
    });

    testWidgets('steppers change one target each', (tester) async {
      final calls = ExerciseCalls();
      await tester.pumpApp(view(const AsyncData(planState), calls: calls));
      await tester.tap(find.bySemanticsLabel('One set more'));
      await tester.tap(find.bySemanticsLabel('One rep less'));
      await tester.tap(find.bySemanticsLabel('15 seconds more'));
      await tester.tap(find.bySemanticsLabel('15 seconds less'));
      await tester.pump();
      expect(calls.targets, [
        {'sets': 4},
        {'reps': 11},
        {'rest': 105},
        {'rest': 75},
      ]);
    });

    testWidgets('weight step choices', (tester) async {
      final calls = ExerciseCalls();
      await tester.pumpApp(view(const AsyncData(planState), calls: calls));
      await tapKey(tester, const Key('plan_step_1.25'));
      // Tapping the selected one (1 kg for this machine) does nothing.
      await tapKey(tester, const Key('plan_step_1.0'));
      expect(calls.targets, [
        {'step': 1.25},
      ]);
    });

    testWidgets('limits: steppers stop at the edges', (tester) async {
      const plan = WorkoutPlan(
        days: [
          WorkoutDay(
            id: 'd',
            name: LocalizedName(ar: 'ي', en: 'D'),
            exercises: [
              Exercise(
                id: 'max',
                name: LocalizedName(ar: 'أ', en: 'Max'),
                targetSets: 10,
                targetReps: 100,
                restSeconds: 600,
                weightStep: 0.25,
              ),
              Exercise(
                id: 'min',
                name: LocalizedName(ar: 'ب', en: 'Min'),
                targetSets: 1,
                targetReps: 1,
                restSeconds: 0,
              ),
            ],
          ),
        ],
      );
      final calls = ExerciseCalls();
      await tester.pumpApp(
        view(
          const AsyncData(PlanEditorState(plan: plan)),
          dayId: 'd',
          exerciseId: 'max',
          calls: calls,
        ),
      );
      await tester.tap(find.bySemanticsLabel('One set more'));
      await tester.tap(find.bySemanticsLabel('One rep more'));
      await tester.tap(find.bySemanticsLabel('15 seconds more'));
      // An unusual stored step (0.25) is shown as a choice too.
      expect(find.byKey(const Key('plan_step_0.25')), findsOneWidget);
      await tester.pumpApp(
        view(
          const AsyncData(PlanEditorState(plan: plan)),
          dayId: 'd',
          exerciseId: 'min',
          calls: calls,
        ),
      );
      await tester.tap(find.bySemanticsLabel('One set less'));
      await tester.tap(find.bySemanticsLabel('One rep less'));
      await tester.tap(find.bySemanticsLabel('15 seconds less'));
      expect(calls.targets, isEmpty);
    });

    testWidgets('superset switch; rest belongs to the pair', (tester) async {
      final calls = ExerciseCalls();
      await tester.pumpApp(
        view(
          const AsyncData(planState),
          exerciseId: 'alternating_db_curl',
          calls: calls,
        ),
      );
      expect(find.text('After the pair'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('15 seconds more'));
      expect(calls.targets, isEmpty);
      await tapKey(tester, const Key('plan_superset_switch'));
      expect(calls.supersets, [false]);
    });

    testWidgets('rename and delete (confirmed)', (tester) async {
      final calls = ExerciseCalls();
      await tester.pumpApp(view(const AsyncData(planState), calls: calls));
      await tapKey(tester, const Key('plan_rename_exercise'));
      await tester.enterText(
        find.byKey(const Key('plan_name_en')),
        'Front Raise',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plan_name_save')));
      await tester.pumpAndSettle();
      expect(calls.renamed.single.en, 'Front Raise');

      await tapKey(tester, const Key('plan_delete_exercise'));
      expect(find.text('Delete "Dumbbell Front Raise"?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('plan_delete_confirm')));
      await tester.pumpAndSettle();
      expect(calls.deletes, 1);
    });

    testWidgets('locked: nothing can change', (tester) async {
      final calls = ExerciseCalls();
      await tester.pumpApp(
        view(
          const AsyncData(lockedState),
          dayId: 'day-1',
          exerciseId: 'flat_db_press',
          calls: calls,
        ),
      );
      expect(find.byKey(const Key('plan_rename_exercise')), findsNothing);
      expect(find.byKey(const Key('plan_delete_exercise')), findsNothing);
      await tester.tap(find.bySemanticsLabel('One set more'));
      await tapKey(tester, const Key('plan_step_5.0'));
      expect(calls.targets, isEmpty);
    });

    testWidgets('unknown or hostile ids: not in your plan', (tester) async {
      for (final (day, ex) in [
        ('day-2', 'nope'),
        ('nope', 'db_front_raise'),
        ('day-2', '<script>'),
        ('day-1', 'db_front_raise'),
      ]) {
        final calls = ExerciseCalls();
        await tester.pumpApp(
          view(
            const AsyncData(planState),
            dayId: day,
            exerciseId: ex,
            calls: calls,
          ),
        );
        expect(find.text("This exercise isn't in your plan."), findsOneWidget);
        await tester.tap(find.text('Back to your plan'));
        expect(calls.backs, 1);
      }
    });

    testWidgets('failed save, error, loading', (tester) async {
      final calls = ExerciseCalls();
      await tester.pumpApp(
        view(
          const AsyncData(
            PlanEditorState(
              plan: WorkoutPlan(days: []),
              saveFailure: UnknownFailure(),
            ),
          ),
          calls: calls,
        ),
      );
      await tester.tap(find.byKey(const Key('plan_retry_save')));
      expect(calls.saveRetries, 1);
      await tester.pumpApp(
        view(
          const AsyncError(ValidationFailure(), StackTrace.empty),
          calls: calls,
        ),
      );
      await tester.tap(find.text('Try again'));
      expect(calls.retries, 1);
      await tester.pumpApp(view(const AsyncLoading()));
      expect(find.byType(LoadingView), findsOneWidget);
    });

    testWidgets('Arabic', (tester) async {
      await tester.pumpApp(
        view(const AsyncData(planState)),
        locale: const Locale('ar'),
      );
      expect(find.text('الأهداف'), findsOneWidget);
      expect(find.text('خطوة الوزن'), findsOneWidget);
    });
  });

  screensUiTests({
    'plan_exercise': () => view(const AsyncData(planState)),
    'plan_exercise_superset': () =>
        view(const AsyncData(planState), exerciseId: 'alternating_db_curl'),
    'plan_exercise_captain_only': () => view(
      const AsyncData(captainOnlyState),
      dayId: 'day-1',
      exerciseId: 'flat_db_press',
    ),
    'plan_exercise_targets_only': () => view(
      const AsyncData(targetsOnlyState),
      dayId: 'day-1',
      exerciseId: 'flat_db_press',
    ),
    'plan_exercise_locked': () => view(
      const AsyncData(lockedState),
      dayId: 'day-1',
      exerciseId: 'flat_db_press',
    ),
    'plan_exercise_not_found': () =>
        view(const AsyncData(planState), exerciseId: 'nope'),
    'plan_exercise_error': () =>
        view(const AsyncError(NetworkFailure(), StackTrace.empty)),
  });
}
