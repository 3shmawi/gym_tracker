import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/presentation/plan_day_view.dart';
import 'package:gym_tracker/features/workout/presentation/plan_editor_controller.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/plan_widgets.dart';
import 'package:gym_tracker/l10n/l10n.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';
import 'plan_samples.dart';

class DayCalls {
  final opened = <String>[];
  final added = <LocalizedName>[];
  final renamedDay = <LocalizedName>[];
  final renamed = <(String, LocalizedName)>[];
  final deleted = <String>[];
  final moved = <(int, int)>[];
  final supersets = <(String, bool)>[];
  int retries = 0;
  int saveRetries = 0;
  int backs = 0;
  int resumes = 0;
}

Widget view(
  AsyncValue<PlanEditorState> state, {
  String dayId = 'day-2',
  DayCalls? calls,
}) {
  final c = calls ?? DayCalls();
  return PlanDayView(
    state: state,
    dayId: dayId,
    onRetry: () => c.retries++,
    onRetrySave: () => c.saveRetries++,
    onBackToPlan: () => c.backs++,
    onOpenExercise: c.opened.add,
    onRenameDay: c.renamedDay.add,
    onAddExercise: c.added.add,
    onRenameExercise: (id, name) => c.renamed.add((id, name)),
    onDeleteExercise: c.deleted.add,
    onMoveExercise: (from, to) => c.moved.add((from, to)),
    onSetSuperset: (id, {required withNext}) => c.supersets.add((id, withNext)),
    onResumeWorkout: () => c.resumes++,
  );
}

/// Finds text ignoring the LTR isolates around numbers.
Finder plain(String text) => find.byWidgetPredicate(
  (w) => w is Text && w.data?.replaceAll(RegExp('[\u2066\u2069]'), '') == text,
);

void main() {
  group('PlanDayView', () {
    testWidgets('a gym that keeps the structure: no rename, add or ⋯', (
      tester,
    ) async {
      await tester.pumpApp(
        view(const AsyncData(targetsOnlyState), dayId: 'day-1'),
      );
      expect(find.byKey(const Key('plan_rename_day')), findsNothing);
      expect(find.byKey(const Key('plan_add_exercise')), findsNothing);
      expect(find.byKey(const Key('plan_managed_banner')), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsNothing);
      expect(find.byIcon(Icons.drag_indicator), findsNothing);
    });

    testWidgets('exercises with targets, supersets as A/B pairs', (
      tester,
    ) async {
      await tester.pumpApp(view(const AsyncData(planState)));
      expect(find.text('Shoulders & Arms'), findsOneWidget);
      expect(plain('Day 2 of 5 · كتف ودراع'), findsOneWidget);
      expect(find.text('Dumbbell Shoulder Press'), findsOneWidget);
      expect(plain('3×12 · rest 90 s · step 2.5 kg'), findsWidgets);
      // Two superset pairs on day 2.
      expect(find.text('A'), findsNWidgets(2));
      expect(find.text('B'), findsNWidgets(2));
      expect(plain('Superset · rest after both 90 s'), findsNWidgets(2));
    });

    testWidgets('tap an exercise to edit its targets', (tester) async {
      final calls = DayCalls();
      await tester.pumpApp(view(const AsyncData(planState), calls: calls));
      await tester.tap(find.text('Dumbbell Shrug'));
      expect(calls.opened, ['db_shrug']);
    });

    testWidgets('add an exercise and rename the day', (tester) async {
      final calls = DayCalls();
      await tester.pumpApp(view(const AsyncData(planState), calls: calls));
      await tester.tap(find.byKey(const Key('plan_add_exercise')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('plan_name_ar')), 'سحب');
      await tester.enterText(find.byKey(const Key('plan_name_en')), 'Row');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plan_name_save')));
      await tester.pumpAndSettle();
      expect(calls.added, [const LocalizedName(ar: 'سحب', en: 'Row')]);

      await tester.tap(find.byKey(const Key('plan_rename_day')));
      await tester.pumpAndSettle();
      // The sheet starts with the current names.
      expect(find.text('كتف ودراع'), findsWidgets);
      await tester.enterText(find.byKey(const Key('plan_name_en')), 'Arms');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plan_name_save')));
      await tester.pumpAndSettle();
      expect(calls.renamedDay.single.en, 'Arms');
      expect(calls.renamedDay.single.ar, 'كتف ودراع');
    });

    testWidgets('⋯ → superset, move, delete', (tester) async {
      final calls = DayCalls();
      await tester.pumpApp(view(const AsyncData(planState), calls: calls));
      Future<void> more(String name) async {
        await tester.tap(find.byTooltip(l10nEn.planOptions(name)));
        await tester.pumpAndSettle();
      }

      await more('Dumbbell Front Raise');
      await tester.tap(find.byKey(const Key('plan_action_superset')));
      await tester.pumpAndSettle();
      expect(calls.supersets, [('db_front_raise', true)]);

      await more('Dumbbell Front Raise');
      await tester.tap(find.byKey(const Key('plan_action_moveDown')));
      await tester.pumpAndSettle();
      expect(calls.moved, [(1, 2)]);

      await more('Dumbbell Front Raise');
      await tester.tap(find.byKey(const Key('plan_action_delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete "Dumbbell Front Raise"?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('plan_delete_confirm')));
      await tester.pumpAndSettle();
      expect(calls.deleted, ['db_front_raise']);
    });

    testWidgets('the last exercise has no superset switch to turn on', (
      tester,
    ) async {
      final calls = DayCalls();
      await tester.pumpApp(view(const AsyncData(planState), calls: calls));
      final more = find.byTooltip(l10nEn.planOptions('Rope Pushdown'));
      await tester.ensureVisible(more);
      await tester.pumpAndSettle();
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(find.text('The last exercise has no next one'), findsOneWidget);
      await tester.tap(find.byKey(const Key('plan_action_superset')));
      await tester.pumpAndSettle();
      expect(calls.supersets, isEmpty);
    });

    testWidgets('the day of the workout in progress is read-only', (
      tester,
    ) async {
      final calls = DayCalls();
      await tester.pumpApp(
        view(const AsyncData(lockedState), dayId: 'day-1', calls: calls),
      );
      expect(find.text(l10nEn.planLocked), findsOneWidget);
      expect(find.byKey(const Key('plan_rename_day')), findsNothing);
      expect(find.byKey(const Key('plan_add_exercise')), findsNothing);
      expect(find.byIcon(Icons.drag_indicator), findsNothing);
      expect(find.byIcon(Icons.more_horiz), findsNothing);
      await tester.tap(find.byKey(const Key('plan_resume_workout')));
      expect(calls.resumes, 1);
    });

    testWidgets('empty day: add the first exercise', (tester) async {
      await tester.pumpApp(
        view(const AsyncData(emptyDayState), dayId: 'new-day'),
      );
      expect(find.text('This day is empty'), findsOneWidget);
      await tester.tap(find.byKey(const Key('plan_add_exercise')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan_name_ar')), findsOneWidget);
    });

    testWidgets('unknown or hostile day ids: not in your plan', (tester) async {
      for (final id in ['nope', '../../etc', "'; DROP TABLE", '%00', '']) {
        final calls = DayCalls();
        await tester.pumpApp(
          view(const AsyncData(planState), dayId: id, calls: calls),
        );
        expect(find.text("This day isn't in your plan."), findsOneWidget);
        await tester.tap(find.text('Back to your plan'));
        expect(calls.backs, 1);
      }
    });

    testWidgets('failed save, error, loading', (tester) async {
      final calls = DayCalls();
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
      expect(find.text('كتف ودراع'), findsOneWidget);
      expect(plain('3×12 · راحة 90 ث · خطوة 2.5 كجم'), findsWidgets);
    });
  });

  screensUiTests({
    'plan_day': () => view(const AsyncData(planState)),
    'plan_day_captain_only': () =>
        view(const AsyncData(captainOnlyState), dayId: 'day-1'),
    'plan_day_locked': () => view(const AsyncData(lockedState), dayId: 'day-1'),
    'plan_day_empty': () =>
        view(const AsyncData(emptyDayState), dayId: 'new-day'),
    'plan_day_not_found': () => view(const AsyncData(planState), dayId: 'nope'),
    'plan_day_error': () =>
        view(const AsyncError(NetworkFailure(), StackTrace.empty)),
    'plan_exercise_actions_sheet': () => SheetHost(
      background: view(const AsyncData(planState)),
      open: (context) => showPlanActionsSheet(
        context,
        title: 'Dumbbell Front Raise',
        subtitle: context.l10n.planExerciseOf('Shoulders & Arms', 2, 8),
        deleteLabel: context.l10n.planDeleteExercise,
        supersetDetail: context.l10n.planSupersetDetail('Reverse Pec Deck'),
        actions: const {
          PlanAction.rename: true,
          PlanAction.superset: true,
          PlanAction.moveUp: true,
          PlanAction.moveDown: true,
          PlanAction.delete: true,
        },
      ),
    ),
  });
}
