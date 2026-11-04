import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/usecases/summarize_workout.dart';

void main() {
  const summarize = SummarizeWorkout();
  final start = DateTime(2026, 11, 2, 18);
  LoggedSet s(String id, double w, int r) =>
      LoggedSet(exerciseId: id, weight: w, reps: r);

  final history = [
    WorkoutSession(
      dayId: legacyDayId(0),
      finishedAt: DateTime(2026, 10, 30),
      sets: [s('pulldown', 50, 12), s('press', 22.5, 12)],
    ),
  ];

  test('counts sets, volume and duration', () {
    final r = summarize(
      [s('press', 22.5, 12), s('press', 22.5, 11)],
      history,
      startedAt: start,
      now: start.add(const Duration(minutes: 58)),
    );
    expect(r.sets, 2);
    expect(r.volume, 22.5 * 23);
    expect(r.duration, const Duration(minutes: 58));
    expect(r.records, isEmpty);
  });

  test('heavier than ever is a record (once per exercise)', () {
    final r = summarize(
      [s('pulldown', 52.5, 12), s('pulldown', 52.5, 10)],
      history,
      startedAt: start,
      now: start,
    );
    expect(r.records.single.exerciseId, 'pulldown');
    expect(r.records.single.weight, 52.5);
  });

  test('first time on an exercise is not a record', () {
    final r = summarize(
      [s('squat', 60, 12)],
      history,
      startedAt: start,
      now: start,
    );
    expect(r.records, isEmpty);
  });

  test('zero-rep sets are ignored for records', () {
    final r = summarize(
      [s('pulldown', 80, 0)],
      history,
      startedAt: start,
      now: start,
    );
    expect(r.records, isEmpty);
  });

  test('volume counts kg exercises only (not plates or reps)', () {
    final now = DateTime(2026, 11, 4, 18);
    final summary = const SummarizeWorkout()(
      const [
        LoggedSet(exerciseId: 'kg', weight: 50, reps: 10),
        LoggedSet(exerciseId: 'plate', weight: 7, reps: 12),
        LoggedSet(exerciseId: 'abs', weight: 0, reps: 20),
      ],
      const [],
      startedAt: now,
      now: now,
      units: const {'plate': ExerciseUnit.plate, 'abs': ExerciseUnit.reps},
    );
    expect(summary.volume, 500);
  });
}
