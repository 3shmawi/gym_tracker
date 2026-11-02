import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/presentation/plan_editor_controller.dart';
import 'package:gym_tracker/features/workout/presentation/plan_view.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/plan_widgets.dart';
import 'package:gym_tracker/l10n/l10n.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';
import 'plan_samples.dart';

class Calls {
  final opened = <String>[];
  final added = <LocalizedName>[];
  final renamed = <(String, LocalizedName)>[];
  final deleted = <String>[];
  final moved = <(int, int)>[];
  int retries = 0;
  int saveRetries = 0;
}

Widget view(AsyncValue<PlanEditorState> state, [Calls? calls]) {
  final c = calls ?? Calls();
  return PlanView(
    state: state,
    onRetry: () => c.retries++,
    onRetrySave: () => c.saveRetries++,
    onOpenDay: c.opened.add,
    onAddDay: c.added.add,
    onRenameDay: (id, name) => c.renamed.add((id, name)),
    onDeleteDay: c.deleted.add,
    onMoveDay: (from, to) => c.moved.add((from, to)),
  );
}

Future<void> openMore(WidgetTester tester, String dayName) async {
  await tester.tap(find.byTooltip(l10nEn.planOptions(dayName)).first);
  await tester.pumpAndSettle();
}

void main() {
  group('PlanView', () {
    testWidgets('days in order with the next one marked', (tester) async {
      await tester.pumpApp(view(const AsyncData(planState)));
      expect(find.text('Your plan'), findsOneWidget);
      expect(find.text('Chest & Back'), findsNWidgets(2));
      expect(find.text('Legs'), findsOneWidget);
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Saves as you go'), findsOneWidget);
      expect(find.byKey(const Key('plan_add_day')), findsOneWidget);
    });

    testWidgets('tapping a day opens it', (tester) async {
      final calls = Calls();
      await tester.pumpApp(view(const AsyncData(planState), calls));
      await tester.tap(find.text('Legs'));
      expect(calls.opened, ['day-3']);
    });

    testWidgets('add a day: the name sheet', (tester) async {
      final calls = Calls();
      await tester.pumpApp(view(const AsyncData(planState), calls));
      await tester.tap(find.byKey(const Key('plan_add_day')));
      await tester.pumpAndSettle();
      final save = find.byKey(const Key('plan_name_save'));
      // Nothing typed: can't save.
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(calls.added, isEmpty);
      await tester.enterText(find.byKey(const Key('plan_name_en')), ' Push ');
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      // One language fills both, trimmed.
      expect(calls.added, [const LocalizedName(ar: 'Push', en: 'Push')]);
    });

    testWidgets('names: too long is refused, hostile text is kept', (
      tester,
    ) async {
      final calls = Calls();
      await tester.pumpApp(view(const AsyncData(planState), calls));
      await tester.tap(find.byKey(const Key('plan_add_day')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('plan_name_ar')), 'ب' * 41);
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.planNameTooLong(40)), findsOneWidget);
      await tester.tap(find.byKey(const Key('plan_name_save')));
      await tester.pumpAndSettle();
      expect(calls.added, isEmpty);

      const hostile = "'; DROP TABLE plan;-- <script>";
      await tester.enterText(find.byKey(const Key('plan_name_ar')), hostile);
      await tester.enterText(
        find.byKey(const Key('plan_name_en')),
        'a   b\u202E',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plan_name_save')));
      await tester.pumpAndSettle();
      expect(calls.added, [const LocalizedName(ar: hostile, en: 'a b')]);
    });

    testWidgets('⋯ → rename, move, delete with a confirm', (tester) async {
      final calls = Calls();
      await tester.pumpApp(view(const AsyncData(planState), calls));

      await openMore(tester, 'Legs');
      await tester.tap(find.byKey(const Key('plan_action_rename')));
      await tester.pumpAndSettle();
      expect(find.text('Legs'), findsWidgets);
      await tester.enterText(find.byKey(const Key('plan_name_en')), 'Leg day');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plan_name_save')));
      await tester.pumpAndSettle();
      expect(calls.renamed.single.$1, 'day-3');
      expect(calls.renamed.single.$2.en, 'Leg day');

      await openMore(tester, 'Legs');
      await tester.tap(find.byKey(const Key('plan_action_moveUp')));
      await tester.pumpAndSettle();
      expect(calls.moved, [(2, 1)]);

      await openMore(tester, 'Legs');
      await tester.tap(find.byKey(const Key('plan_action_delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete "Legs"?'), findsOneWidget);
      // Cancel first: nothing deleted.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(calls.deleted, isEmpty);
      await openMore(tester, 'Legs');
      await tester.tap(find.byKey(const Key('plan_action_delete')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plan_delete_confirm')));
      await tester.pumpAndSettle();
      expect(calls.deleted, ['day-3']);
    });

    testWidgets('the last day and the locked day can not be deleted', (
      tester,
    ) async {
      final calls = Calls();
      await tester.pumpApp(view(const AsyncData(emptyDayState), calls));
      await openMore(tester, 'Chest & Triceps');
      expect(find.text('A plan keeps at least one day.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('plan_action_delete')));
      await tester.pumpAndSettle();
      expect(calls.deleted, isEmpty);
    });

    testWidgets('the day of the workout in progress says so', (tester) async {
      final calls = Calls();
      await tester.pumpApp(view(const AsyncData(lockedState), calls));
      expect(find.text('In progress'), findsOneWidget);
      await openMore(tester, 'Chest & Back');
      await tester.tap(find.byKey(const Key('plan_action_delete')));
      await tester.tap(find.byKey(const Key('plan_action_rename')));
      await tester.pumpAndSettle();
      expect(calls.deleted, isEmpty);
      expect(find.byKey(const Key('plan_name_save')), findsNothing);
    });

    testWidgets('empty plan: add the first day', (tester) async {
      await tester.pumpApp(view(const AsyncData(emptyPlanState)));
      expect(find.text('Your plan is empty'), findsOneWidget);
      await tester.tap(find.byKey(const Key('plan_add_first_day')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('plan_name_ar')), findsOneWidget);
    });

    testWidgets('a failed save: try again', (tester) async {
      final calls = Calls();
      await tester.pumpApp(
        view(
          const AsyncData(
            PlanEditorState(
              plan: WorkoutPlan(days: []),
              saveFailure: UnknownFailure(),
            ),
          ),
          calls,
        ),
      );
      expect(find.text("Couldn't save your plan"), findsOneWidget);
      await tester.tap(find.byKey(const Key('plan_retry_save')));
      expect(calls.saveRetries, 1);
    });

    testWidgets('load error: retry; loading', (tester) async {
      final calls = Calls();
      await tester.pumpApp(
        view(const AsyncError(ValidationFailure(), StackTrace.empty), calls),
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
      expect(find.text('خطتك'), findsOneWidget);
      expect(find.text('رجل'), findsOneWidget);
      expect(find.text('الجاي'), findsOneWidget);
    });
  });

  screensUiTests({
    'plan': () => view(const AsyncData(planState)),
    'plan_locked': () => view(const AsyncData(lockedState)),
    'plan_empty': () => view(const AsyncData(emptyPlanState)),
    'plan_save_failed': () => view(
      const AsyncData(
        PlanEditorState(
          plan: WorkoutPlan(days: []),
          saveFailure: UnknownFailure(),
        ),
      ),
    ),
    'plan_error': () =>
        view(const AsyncError(NetworkFailure(), StackTrace.empty)),
    'plan_name_sheet': () => SheetHost(
      background: view(const AsyncData(planState)),
      open: (context) => showPlanNameSheet(
        context,
        title: context.l10n.planAddDay,
        confirmLabel: context.l10n.planAdd,
        // A focused field's cursor handle sits in a screen-sized overlay
        // box that the layout check reads as off screen.
        autofocus: false,
      ),
    ),
    'plan_delete_sheet': () => SheetHost(
      background: view(const AsyncData(planState)),
      open: (context) => showPlanDeleteSheet(
        context,
        title: context.l10n.planDeleteDayTitle('Legs'),
        body: context.l10n.planDeleteDayBody,
        confirmLabel: context.l10n.planDeleteDay,
      ),
    ),
    'plan_day_actions_sheet': () => SheetHost(
      background: view(const AsyncData(planState)),
      open: (context) => showPlanActionsSheet(
        context,
        title: 'Legs',
        subtitle: context.l10n.todayDayOf(3, 5),
        deleteLabel: context.l10n.planDeleteDay,
        actions: const {
          PlanAction.rename: true,
          PlanAction.moveUp: true,
          PlanAction.moveDown: true,
          PlanAction.delete: true,
        },
      ),
    ),
  });
}
