import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/next_workout.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/usecases/get_next_workout.dart';

void main() {
  const get = GetNextWorkout();
  const plan = PlanTemplates.fiveDaySplit;

  WorkoutSession session(int day, DateTime at, [List<LoggedSet>? sets]) =>
      WorkoutSession(
        dayId: legacyDayId(day),
        finishedAt: at,
        sets: sets ?? const [],
      );

  test('starts at day 1 with no history', () {
    final next = get(plan, const [], now: DateTime(2026, 11, 2));
    expect(next.dayIndex, 0);
    expect(next.totalDays, 5);
    expect(next.day.name.ar, 'بنش وضهر');
    expect(next.waitingSince, isNull);
    expect(next.exercises, hasLength(7));
    expect(
      next.exercises.every((e) => e.suggestion.trend == Trend.firstTime),
      isTrue,
    );
  });

  test('advances by finished session, not by date', () {
    final next = get(plan, [
      session(0, DateTime(2026, 11, 2, 19)),
    ], now: DateTime(2026, 11, 3, 18));
    expect(next.dayIndex, 1);
    expect(next.waitingSince, isNull, reason: 'next day is not a skip');
  });

  test('a skipped day keeps the same workout and says it waited', () {
    final next = get(plan, [
      session(0, DateTime(2026, 11, 2, 19)), // Monday
    ], now: DateTime(2026, 11, 5, 18)); // Thursday
    expect(next.dayIndex, 1, reason: 'still day 2, not day 4');
    expect(next.waitingSince, DateTime(2026, 11, 3));
  });

  test('wraps around after the last day', () {
    final next = get(plan, [
      session(4, DateTime(2026, 11, 6)),
    ], now: DateTime(2026, 11, 7));
    expect(next.dayIndex, 0);
  });

  test('uses the latest session even if history is unsorted', () {
    final next = get(plan, [
      session(2, DateTime(2026, 11, 4)),
      session(0, DateTime(2026, 11, 2)),
    ], now: DateTime(2026, 11, 5));
    expect(next.dayIndex, 3);
  });

  test('last sets come from any day with the same exercise', () {
    // Abs is on day 1 and day 4: day 1's sets feed day 4's suggestion.
    final next = get(plan, [
      session(0, DateTime(2026, 11, 2), const [
        LoggedSet(exerciseId: 'abs', weight: 50, reps: 15),
        LoggedSet(exerciseId: 'abs', weight: 50, reps: 15),
        LoggedSet(exerciseId: 'abs', weight: 50, reps: 15),
      ]),
      session(1, DateTime(2026, 11, 3)),
      session(2, DateTime(2026, 11, 4)),
    ], now: DateTime(2026, 11, 5));
    expect(next.dayIndex, 3);
    final abs = next.exercises.firstWhere((e) => e.exercise.id == 'abs');
    expect(abs.lastSets, hasLength(3));
    expect(abs.suggestion, const WeightSuggestion(weight: 55, trend: Trend.up));
  });

  test('a plan without days is rejected', () {
    expect(
      () => get(const WorkoutPlan(days: []), const [], now: DateTime(2026)),
      throwsArgumentError,
    );
  });

  test('a chosen day wins and hides the waiting banner', () {
    final next = get(
      plan,
      [session(0, DateTime(2026, 11, 2))],
      now: DateTime(2026, 11, 9),
      chosenDay: const ChosenDay('day-3'),
    );
    expect(next.dayIndex, 2);
    expect(next.waitingSince, isNull);
  });

  test('an unknown chosen day is ignored', () {
    for (final bad in ['', 'day-0', 'day-6', "'; DROP TABLE plan;--"]) {
      expect(
        get(
          plan,
          const [],
          now: DateTime(2026),
          chosenDay: ChosenDay(bad),
        ).dayIndex,
        0,
        reason: bad,
      );
    }
  });

  group('trained today', () {
    test('a workout finished earlier today', () {
      final next = get(plan, [
        session(0, DateTime(2026, 11, 2, 7)),
      ], now: DateTime(2026, 11, 2, 19));
      expect(next.trainedToday, isTrue);
      expect(next.dayIndex, 1, reason: 'the plan still moves on');
    });

    test('yesterday or never: no', () {
      expect(
        get(plan, [
          session(0, DateTime(2026, 11, 1, 23)),
        ], now: DateTime(2026, 11, 2, 7)).trainedToday,
        isFalse,
      );
      expect(
        get(plan, const [], now: DateTime(2026, 11, 2)).trainedToday,
        isFalse,
      );
    });

    test('resuming a workout in progress is not "another"', () {
      final next = get(
        plan,
        [session(0, DateTime(2026, 11, 2, 7))],
        now: DateTime(2026, 11, 2, 19),
        workoutInProgress: true,
      );
      expect(next.trainedToday, isFalse);
    });
  });

  group('Move games rounds are not plan days', () {
    WorkoutSession round(DateTime at) => WorkoutSession(
      dayId: WorkoutSession.moveDayId,
      finishedAt: at,
      sets: const [LoggedSet(exerciseId: 'push_ups', weight: 0, reps: 20)],
    );

    test('a round after day 2 does not reset the plan to day 1', () {
      final next = get(plan, [
        session(1, DateTime(2026, 11, 2, 19)),
        round(DateTime(2026, 11, 3, 8)),
      ], now: DateTime(2026, 11, 3, 18));
      expect(next.dayIndex, 2);
    });

    test("a round today doesn't mean today's workout is done", () {
      final next = get(plan, [
        session(0, DateTime(2026, 11, 2, 19)),
        round(DateTime(2026, 11, 3, 8)),
      ], now: DateTime(2026, 11, 3, 18));
      expect(next.trainedToday, isFalse);
      expect(next.waitingSince, isNull);
    });

    test('only rounds: still day 1, nothing waiting', () {
      final next = get(plan, [
        round(DateTime(2026, 11, 1, 8)),
        round(DateTime(2026, 11, 2, 8)),
      ], now: DateTime(2026, 11, 5, 18));
      expect(next.dayIndex, 0);
      expect(next.waitingSince, isNull);
    });
  });
}
