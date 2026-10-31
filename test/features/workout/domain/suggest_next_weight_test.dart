import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout.dart';
import 'package:gym_tracker/features/workout/domain/usecases/suggest_next_weight.dart';

const _exercise = PlanExercise(
  exerciseId: 'e1',
  nameEn: 'Chest Press',
  nameAr: 'صدر',
  position: 1,
  sets: 3,
  targetReps: 10,
  restSeconds: 90,
  weightStepKg: 2.5,
);

List<LoggedSet> _sets(List<(double, int)> sets) => [
  for (final (i, (kg, reps)) in sets.indexed)
    LoggedSet(
      id: 's$i',
      sessionId: 'session',
      exerciseId: 'e1',
      setNumber: i + 1,
      weightKg: kg,
      reps: reps,
      loggedAt: DateTime(2026, 1, 1, 10, i),
    ),
];

void main() {
  const suggest = SuggestNextWeight();

  test('first time: no weight suggested', () {
    expect(
      suggest(exercise: _exercise, lastSession: const []),
      const WeightSuggestion(trend: WeightTrend.firstTime),
    );
  });

  test('all sets hit the target: add one step', () {
    expect(
      suggest(
        exercise: _exercise,
        lastSession: _sets([(40, 10), (40, 10), (40, 11)]),
      ),
      const WeightSuggestion(trend: WeightTrend.increase, weightKg: 42.5),
    );
  });

  test('missed the target on one set: keep the weight', () {
    expect(
      suggest(
        exercise: _exercise,
        lastSession: _sets([(40, 10), (40, 9), (40, 8)]),
      ),
      const WeightSuggestion(trend: WeightTrend.keep, weightKg: 40),
    );
  });

  test('fewer sets than planned: keep the weight', () {
    expect(
      suggest(exercise: _exercise, lastSession: _sets([(40, 12), (40, 12)])),
      const WeightSuggestion(trend: WeightTrend.keep, weightKg: 40),
    );
  });

  test('far below the target: drop one step', () {
    expect(
      suggest(
        exercise: _exercise,
        lastSession: _sets([(40, 6), (40, 5), (40, 5)]),
      ),
      const WeightSuggestion(trend: WeightTrend.decrease, weightKg: 37.5),
    );
  });

  test('warm-up sets at a lighter weight are ignored', () {
    expect(
      suggest(
        exercise: _exercise,
        lastSession: _sets([(20, 15), (40, 10), (40, 10), (40, 10)]),
      ),
      const WeightSuggestion(trend: WeightTrend.increase, weightKg: 42.5),
    );
  });

  test('never suggests zero or negative weight', () {
    expect(
      suggest(exercise: _exercise, lastSession: _sets([(2.5, 2), (2.5, 2)])),
      const WeightSuggestion(trend: WeightTrend.keep, weightKg: 2.5),
    );
  });
}
