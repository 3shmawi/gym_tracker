import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/domain/entities/next_workout.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/usecases/get_next_workout.dart';

void main() {
  const get = GetNextWorkout();
  const plan = PlanTemplates.fiveDaySplit;

  WorkoutSession session(int day, DateTime at, [List<LoggedSet>? sets]) =>
      WorkoutSession(dayIndex: day, finishedAt: at, sets: sets ?? const []);

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
    // Day 4 repeats day 1: day 1's sets feed day 4's suggestions.
    final next = get(plan, [
      session(0, DateTime(2026, 11, 2), const [
        LoggedSet(exerciseId: 'wide_lat_pulldown', weight: 50, reps: 12),
        LoggedSet(exerciseId: 'wide_lat_pulldown', weight: 50, reps: 12),
        LoggedSet(exerciseId: 'wide_lat_pulldown', weight: 50, reps: 12),
      ]),
      session(1, DateTime(2026, 11, 3)),
      session(2, DateTime(2026, 11, 4)),
    ], now: DateTime(2026, 11, 5));
    expect(next.dayIndex, 3);
    final pulldown = next.exercises.firstWhere(
      (e) => e.exercise.id == 'wide_lat_pulldown',
    );
    expect(pulldown.lastSets, hasLength(3));
    expect(
      pulldown.suggestion,
      const WeightSuggestion(weight: 52.5, trend: Trend.up),
    );
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
      chosenDay: 2,
    );
    expect(next.dayIndex, 2);
    expect(next.waitingSince, isNull);
  });

  test('an out-of-range chosen day is ignored', () {
    for (final bad in [-1, 5, 999]) {
      expect(
        get(plan, const [], now: DateTime(2026), chosenDay: bad).dayIndex,
        0,
        reason: '$bad',
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
}
