import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/workout_pill_view.dart';
import 'package:gym_tracker/features/workout/presentation/workout_pill_host.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';
import 'active_workout_view_test.dart' as screen;

final _now = DateTime(2026, 11, 2, 18, 30);

WorkoutPillData? _data(
  ActiveWorkout? active, {
  String? day = 'Chest & Back',
  int? number = 1,
  bool empty = false,
  DateTime? now,
}) => workoutPillData(
  active: active,
  nextDayName: day,
  nextDayNumber: number,
  nextDayEmpty: empty,
  now: now ?? _now,
  lang: 'en',
);

/// Every state of the pill on one screen, plus the edge tab (board 5).
Widget _board() => AppScaffold(
  title: 'Pill',
  body: Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      spacing: 16,
      children: [
        for (final data in <WorkoutPillData>[
          const PillStart(dayNumber: 2, dayName: 'Shoulders & Arms'),
          const PillActive(
            exerciseId: 'incline_machine_press',
            exerciseName: 'Incline Machine Press',
            done: 2,
            total: 7,
          ),
          PillResting(
            endsAt: _now.add(const Duration(seconds: 72)),
            totalSeconds: 90,
            nextSet: 3,
          ),
          const PillRestOver(nextSet: 3, amount: '50 kg'),
        ])
          WorkoutPillView(data: data, now: _now, onTap: () {}),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: WorkoutPillTab(atStart: true, progress: 0.3, onTap: () {}),
        ),
      ],
    ),
  ),
);

void main() {
  group('workoutPillData', () {
    test('no workout in progress: start the waiting day', () {
      final data = _data(null)! as PillStart;
      expect(data.dayNumber, 1);
      expect(data.dayName, 'Chest & Back');
    });

    test('no plan, or an empty day: no pill', () {
      expect(_data(null, day: null, number: null), isNull);
      expect(_data(null, empty: true), isNull);
    });

    test('in progress: resume, with the current exercise and progress', () {
      final data = _data(screen.logging())! as PillActive;
      expect(data.exerciseId, 'wide_lat_pulldown');
      expect(data.exerciseName, 'Wide Lat Pulldown');
      expect(data.done, 1);
      expect(data.total, 7);
    });

    test('resting: counts down to the next set', () {
      final data = _data(screen.resting())! as PillResting;
      expect(data.nextSet, 3);
      expect(data.totalSeconds, 90);
      expect(data.endsAt, _now.add(const Duration(seconds: 72)));
    });

    test('the rest ran out away from the screen: go, with the weight', () {
      final data =
          _data(screen.resting(), now: _now.add(const Duration(minutes: 2)))!
              as PillRestOver;
      expect(data.nextSet, 3);
      expect(data.amount, isNotNull);
    });
  });

  test('hidden on the workout screen, on home and before the app', () {
    for (final path in [
      AppRoutes.workout,
      // Home has its own Start / Continue button.
      AppRoutes.home,
      AppRoutes.welcome,
      AppRoutes.join,
      AppRoutes.joinScan,
      AppRoutes.joinCode('ABC123'),
    ]) {
      expect(workoutPillHiddenOn(path), isTrue, reason: path);
    }
    for (final path in [
      AppRoutes.settings,
      AppRoutes.plan,
      AppRoutes.progress,
      AppRoutes.library,
      AppRoutes.libraryExercise('flat_db_press'),
      AppRoutes.profile,
      // Hostile paths are just "another screen": shown, never a crash.
      '/workout/../join',
      "/'; drop table",
    ]) {
      expect(workoutPillHiddenOn(path), isFalse, reason: path);
    }
  });

  group(WorkoutPillView, () {
    testWidgets('one tap, with a label that says what it does', (tester) async {
      var taps = 0;
      await tester.pumpApp(
        Center(
          child: WorkoutPillView(
            data: const PillActive(
              exerciseId: 'flat_db_press',
              exerciseName: 'Flat Dumbbell Press',
              done: 2,
              total: 7,
            ),
            now: _now,
            onTap: () => taps++,
          ),
        ),
      );
      expect(find.text('Resume workout'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Resume workout: Flat Dumbbell Press, 2 of 7 exercises done',
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('workout_pill')));
      expect(taps, 1);
    });

    testWidgets('resting: the clock counts down', (tester) async {
      await tester.pumpApp(
        Center(
          child: WorkoutPillView(
            data: PillResting(
              endsAt: _now.add(const Duration(seconds: 72)),
              totalSeconds: 90,
              nextSet: 3,
            ),
            now: _now,
            onTap: () {},
          ),
        ),
      );
      expect(find.textContaining('1:12'), findsOneWidget);
      expect(find.text('Next: set 3'), findsOneWidget);
    });

    testWidgets('a rest end in the past never shows a negative time', (
      tester,
    ) async {
      await tester.pumpApp(
        Center(
          child: WorkoutPillView(
            data: PillResting(
              endsAt: _now.subtract(const Duration(seconds: 30)),
              totalSeconds: 90,
              nextSet: 3,
            ),
            now: _now,
            onTap: () {},
          ),
        ),
      );
      expect(find.textContaining('0:00'), findsOneWidget);
    });

    testWidgets('Arabic', (tester) async {
      await tester.pumpApp(
        Center(
          child: WorkoutPillView(
            data: const PillStart(dayNumber: 2, dayName: 'كتف ودراع'),
            now: _now,
            onTap: () {},
          ),
        ),
        locale: const Locale('ar'),
      );
      expect(find.text('ابدأ التمرين'), findsOneWidget);
      expect(find.text('اليوم 2 · كتف ودراع'), findsOneWidget);
    });

    testWidgets('the edge tab brings it back', (tester) async {
      var taps = 0;
      await tester.pumpApp(
        Center(
          child: WorkoutPillTab(
            atStart: false,
            progress: 0.5,
            onTap: () => taps++,
          ),
        ),
      );
      await tester.tap(find.bySemanticsLabel('Show the workout button'));
      expect(taps, 1);
    });
  });

  screensUiTests({'workout_pill': _board});
}
