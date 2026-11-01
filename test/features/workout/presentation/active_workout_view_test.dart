import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_draft.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/usecases/get_next_workout.dart';
import 'package:gym_tracker/features/workout/domain/usecases/summarize_workout.dart';
import 'package:gym_tracker/features/workout/domain/usecases/workout_flow.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_view.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';

final _now = DateTime(2026, 11, 2, 18, 30);

/// Last time: Wide Lat Pulldown 50×12 ×3, Flat DB Press 22.5×12, 12, 11.
final _history = [
  WorkoutSession(
    dayIndex: 4,
    finishedAt: DateTime(2026, 10, 30),
    sets: [
      for (final r in [12, 12, 11])
        LoggedSet(exerciseId: 'flat_db_press', weight: 22.5, reps: r),
      for (var i = 0; i < 3; i++)
        const LoggedSet(exerciseId: 'wide_lat_pulldown', weight: 50, reps: 12),
    ],
  ),
];

/// Builds the screen state like the controller does.
ActiveWorkout workout(int day, List<LoggedSet> sets, {DateTime? restEndsAt}) {
  const plan = PlanTemplates.fiveDaySplit;
  final next = const GetNextWorkout()(
    plan,
    _history,
    now: _now,
    chosenDay: day,
  );
  final draft = WorkoutDraft(
    dayIndex: day,
    startedAt: _now.subtract(const Duration(minutes: 17)),
    sets: sets,
    restEndsAt: restEndsAt,
  );
  return ActiveWorkout(
    day: next.day,
    dayIndex: day,
    totalDays: next.totalDays,
    draft: draft,
    previews: next.exercises,
    cursor: const WorkoutFlow().next(next.day, sets, {
      for (final p in next.exercises) p.exercise.id: p.lastSets,
    }),
    summary: const SummarizeWorkout()(
      sets,
      _history,
      startedAt: draft.startedAt,
      now: _now,
    ),
  );
}

LoggedSet s(String id, double w, int r) =>
    LoggedSet(exerciseId: id, weight: w, reps: r);

final List<LoggedSet> press3 = [
  for (var i = 0; i < 3; i++) s('flat_db_press', 22.5, 12),
];

/// Set 2 of the pulldown, after set 1 at the suggested 52.5.
ActiveWorkout logging() =>
    workout(0, [...press3, s('wide_lat_pulldown', 52.5, 12)]);

ActiveWorkout resting() => workout(0, [
  ...press3,
  s('wide_lat_pulldown', 52.5, 12),
  s('wide_lat_pulldown', 52.5, 11),
], restEndsAt: _now.add(const Duration(seconds: 72)));

/// Day 2, first superset, set 1 of the curl (A), straight to kickback (B).
ActiveWorkout superset() => workout(1, [
  for (final id in [
    'db_shoulder_press',
    'db_front_raise',
    'reverse_pec_deck',
    'db_shrug',
  ])
    for (var i = 0; i < 3; i++) s(id, 10, 12),
]);

ActiveWorkout allDone() {
  final day = PlanTemplates.fiveDaySplit.days[0];
  return workout(0, [
    for (final (i, _) in const WorkoutFlow().order(day))
      s(day.exercises[i].id, i == 1 ? 52.5 : 20, day.exercises[i].targetReps),
  ]);
}

class Calls {
  final logs = <(double, int)>[];
  final edits = <(int, double, int)>[];
  final deletes = <int>[];
  int add15 = 0;
  int endRest = 0;
  int finish = 0;
  int close = 0;
  int retry = 0;

  ActiveWorkoutActions get actions => ActiveWorkoutActions(
    onLog: (w, r) => logs.add((w, r)),
    onEditSet: (i, w, r) => edits.add((i, w, r)),
    onDeleteSet: deletes.add,
    onAdd15: () => add15++,
    onEndRest: () => endRest++,
    onFinish: () async => finish++,
    onClose: () => close++,
    onRetry: () => retry++,
  );
}

Widget view(
  AsyncValue<ActiveWorkout?> state, {
  Calls? calls,
  DateTime Function()? now,
}) => ActiveWorkoutView(
  state: state,
  actions: (calls ?? Calls()).actions,
  now: now ?? () => _now,
);

void main() {
  group(ActiveWorkoutView, () {
    testWidgets('one tap logs the prefilled set', (tester) async {
      final calls = Calls();
      await tester.pumpApp(view(AsyncData(logging()), calls: calls));
      expect(find.text('Wide Lat Pulldown'), findsOneWidget);
      expect(find.text('Set 2 of 3'), findsOneWidget);
      await tester.tap(find.byKey(const Key('log_set_button')));
      expect(calls.logs, [(52.5, 12)]);
    });

    testWidgets('steppers adjust weight by the exercise step', (tester) async {
      final calls = Calls();
      await tester.pumpApp(view(AsyncData(logging()), calls: calls));
      await tester.tap(find.bySemanticsLabel('Add 2.5 kg'));
      await tester.tap(find.bySemanticsLabel('One rep less'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('log_set_button')));
      expect(calls.logs, [(55.0, 11)]);
    });

    testWidgets('rest: countdown, +15 s, skip, and what is next', (
      tester,
    ) async {
      final calls = Calls();
      await tester.pumpApp(view(AsyncData(resting()), calls: calls));
      expect(find.text('1:12'), findsOneWidget);
      expect(
        find.text('Next: Wide Lat Pulldown · \u206652.5 × 11\u2069'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('log_set_button')), findsNothing);
      await tester.tap(find.byKey(const Key('rest_add_15')));
      await tester.tap(find.byKey(const Key('rest_skip')));
      expect((calls.add15, calls.endRest), (1, 1));
    });

    testWidgets('rest over: ends the rest by itself', (tester) async {
      final calls = Calls();
      var now = _now;
      await tester.pumpApp(
        view(AsyncData(resting()), calls: calls, now: () => now),
      );
      now = now.add(const Duration(seconds: 73));
      await tester.pump(const Duration(milliseconds: 300));
      expect(calls.endRest, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(calls.endRest, 1, reason: 'only once');
    });

    testWidgets('superset: shows both and says no rest', (tester) async {
      await tester.pumpApp(view(AsyncData(superset())));
      await tester.pumpAndSettle(); // scrolls the current exercise to the top
      expect(find.text('Alternating Dumbbell Curl'), findsOneWidget);
      expect(find.text('Cable Kickback'), findsOneWidget);
      expect(
        find.text('Then straight to Cable Kickback, no rest'),
        findsOneWidget,
      );
    });

    testWidgets('tap a logged set to edit it', (tester) async {
      final calls = Calls();
      await tester.pumpApp(view(AsyncData(logging()), calls: calls));
      await tester.tap(find.byKey(const Key('set_chip_wide_lat_pulldown_1')));
      await tester.pumpAndSettle();
      expect(find.text('Edit set 1'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.bySemanticsLabel('One rep less'),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('edit_save')));
      await tester.pumpAndSettle();
      expect(calls.edits, [(3, 52.5, 11)]);
    });

    testWidgets('delete needs a second tap', (tester) async {
      final calls = Calls();
      await tester.pumpApp(view(AsyncData(logging()), calls: calls));
      await tester.tap(find.byKey(const Key('set_chip_wide_lat_pulldown_1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('edit_delete')));
      await tester.pump();
      expect(calls.deletes, isEmpty);
      expect(find.text('Tap again to delete'), findsOneWidget);
      await tester.tap(find.byKey(const Key('edit_delete')));
      await tester.pumpAndSettle();
      expect(calls.deletes, [3]);
    });

    testWidgets('all done: finish sheet with summary, then finish', (
      tester,
    ) async {
      final calls = Calls();
      await tester.pumpApp(view(AsyncData(allDone()), calls: calls));
      expect(find.text('All sets done'), findsOneWidget);
      await tester.tap(find.byKey(const Key('finish_button')));
      await tester.pumpAndSettle();
      expect(find.text('Done: Chest & Back'), findsOneWidget);
      expect(find.text('21/21'), findsOneWidget);
      expect(find.text('New record'), findsOneWidget);
      await tester.tap(find.byKey(const Key('finish_confirm')));
      await tester.pumpAndSettle();
      expect(calls.finish, 1);
    });

    testWidgets('finishing early says how many sets are left', (tester) async {
      final calls = Calls();
      await tester.pumpApp(view(AsyncData(logging()), calls: calls));
      await tester.tap(find.byKey(const Key('workout_finish_menu')));
      await tester.pumpAndSettle();
      expect(find.text('17 sets left'), findsOneWidget);
      await tester.tap(find.byKey(const Key('finish_keep_going')));
      await tester.pumpAndSettle();
      expect(calls.finish, 0);
    });

    testWidgets('no workout: a way home', (tester) async {
      final calls = Calls();
      await tester.pumpApp(view(const AsyncData(null), calls: calls));
      await tester.tap(find.byKey(const Key('workout_go_home')));
      expect(calls.close, 1);
    });

    testWidgets('error: retry', (tester) async {
      final calls = Calls();
      await tester.pumpApp(
        view(
          const AsyncError(ValidationFailure(), StackTrace.empty),
          calls: calls,
        ),
        locale: const Locale('ar'),
      );
      await tester.tap(find.byType(FilledButton));
      expect(calls.retry, 1);
    });

    testWidgets('Arabic: numbers stay in order', (tester) async {
      await tester.pumpApp(
        view(AsyncData(logging())),
        locale: const Locale('ar'),
      );
      expect(find.text('مجموعة 2 من 3'), findsOneWidget);
      expect(find.text('سجّل \u206652.5 × 12\u2069'), findsOneWidget);
    });
  });

  screensUiTests({
    'active_workout_log': () => view(AsyncData(logging())),
    'active_workout_rest': () => view(AsyncData(resting())),
    'active_workout_superset': () => view(AsyncData(superset())),
    'active_workout_done': () => view(AsyncData(allDone())),
    'active_workout_none': () => view(const AsyncData(null)),
    'active_workout_error': () =>
        view(const AsyncError(NetworkFailure(), StackTrace.empty)),
  });
}
