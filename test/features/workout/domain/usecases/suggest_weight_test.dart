import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/workout/domain/entities/next_workout.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/usecases/suggest_weight.dart';

const _exercise = Exercise(
  id: 'x',
  name: LocalizedName(ar: 'س', en: 'X'),
);

List<LoggedSet> sets(List<(double, int)> s) => [
  for (final (w, r) in s) LoggedSet(exerciseId: 'x', weight: w, reps: r),
];

void main() {
  const suggest = SuggestWeight();

  test('hit every rep → up one step (Wide Lat Pulldown 50×12 ×3)', () {
    expect(
      suggest(_exercise, sets([(50, 12), (50, 12), (50, 12)])),
      const WeightSuggestion(weight: 52.5, trend: Trend.up),
    );
  });

  test('one rep short → keep (Flat DB Press 22.5×12, 12, 11)', () {
    expect(
      suggest(_exercise, sets([(22.5, 12), (22.5, 12), (22.5, 11)])),
      const WeightSuggestion(weight: 22.5, trend: Trend.keep),
    );
  });

  test('average within 2 reps → keep', () {
    expect(
      suggest(_exercise, sets([(40, 10), (40, 10), (40, 10)])).trend,
      Trend.keep,
    );
  });

  test('well short → down one step', () {
    expect(
      suggest(_exercise, sets([(40, 9), (40, 8), (40, 7)])),
      const WeightSuggestion(weight: 37.5, trend: Trend.down),
    );
  });

  test('down never goes below zero', () {
    expect(suggest(_exercise, sets([(0, 4)])).weight, 0);
  });

  test('no history → first time, no weight', () {
    expect(
      suggest(_exercise, const []),
      const WeightSuggestion(trend: Trend.firstTime),
    );
  });

  test('only zero-rep sets count as no history', () {
    expect(suggest(_exercise, sets([(40, 0)])).trend, Trend.firstTime);
  });

  test('fewer sets than the target is not an increase', () {
    expect(suggest(_exercise, sets([(50, 12), (50, 12)])).trend, Trend.keep);
  });

  test('a lighter warm-up set does not block the increase', () {
    expect(
      suggest(_exercise, sets([(30, 12), (50, 12), (50, 12), (50, 12)])),
      const WeightSuggestion(weight: 52.5, trend: Trend.up),
    );
  });

  test('uses the exercise weight step', () {
    const abs = Exercise(
      id: 'x',
      name: LocalizedName(ar: 'بطن', en: 'Abs'),
      targetReps: 15,
      weightStep: 5,
    );
    expect(suggest(abs, sets([(10, 15), (10, 15), (10, 15)])).weight, 15);
  });

  test('plates move one plate (#7 ×3 hit → #8)', () {
    final plate = _exercise.copyWith(unit: ExerciseUnit.plate);
    expect(
      suggest(plate, sets([(7, 12), (7, 12), (7, 12)])),
      const WeightSuggestion(weight: 8, trend: Trend.up),
    );
  });

  test('reps only keeps weight 0, the trend still says push', () {
    final reps = _exercise.copyWith(unit: ExerciseUnit.reps);
    expect(
      suggest(reps, sets([(0, 12), (0, 12), (0, 12)])),
      const WeightSuggestion(weight: 0, trend: Trend.up),
    );
  });
}
