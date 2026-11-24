import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/presentation/workout_format.dart';

List<LoggedSet> s(List<(double, int)> sets) => [
  for (final (w, r) in sets) LoggedSet(exerciseId: 'x', weight: w, reps: r),
];

void main() {
  test('weights drop trailing zeros', () {
    expect(WorkoutFormat.weight(52.5), '52.5');
    expect(WorkoutFormat.weight(50), '50');
    expect(WorkoutFormat.weight(1.25), '1.25');
    expect(WorkoutFormat.weight(0), '0');
  });

  test('identical sets collapse: 50×12 ×3', () {
    expect(WorkoutFormat.sets(s([(50, 12), (50, 12), (50, 12)])), '50×12 ×3');
  });

  test('same weight lists reps: 22.5×12, 12, 11', () {
    expect(
      WorkoutFormat.sets(s([(22.5, 12), (22.5, 12), (22.5, 11)])),
      '22.5×12, 12, 11',
    );
  });

  test('mixed weights list every set', () {
    expect(WorkoutFormat.sets(s([(30, 12), (50, 10)])), '30×12, 50×10');
  });

  test('single set and none', () {
    expect(WorkoutFormat.sets(s([(40, 8)])), '40×8');
    expect(WorkoutFormat.sets(const []), '');
  });

  test('target is sets×reps', () {
    expect(WorkoutFormat.target(3, 12), '3×12');
    expect(WorkoutFormat.target(2, 6, 10), '2×6–10');
  });

  test('holds read as a clock in both languages (plank_hold.md)', () {
    const sec = ExerciseUnit.seconds;
    expect(WorkoutFormat.hold(30), '0:30');
    expect(WorkoutFormat.hold(75), '1:15');
    expect(WorkoutFormat.hold(-5), '0:00');
    expect(WorkoutFormat.set(0, 45, sec), '0:45');
    expect(WorkoutFormat.amount(0, sec), '');
    LoggedSet h(int s) => LoggedSet(exerciseId: 'plank', weight: 0, reps: s);
    expect(WorkoutFormat.sets([h(30), h(30), h(30)], sec), '0:30 ×3');
    expect(WorkoutFormat.sets([h(45), h(40)], sec), '0:45, 0:40');
    expect(WorkoutFormat.weightTimesReps(0, 60, sec), '\u20661:00\u2069');
    expect(ExerciseUnit.seconds.hasWeight, isFalse);
    expect(ExerciseUnit.reps.hasWeight, isFalse);
    expect(ExerciseUnit.plate.hasWeight, isTrue);
    expect(ExerciseUnit.parse('seconds'), ExerciseUnit.seconds);
  });

  test('ltr isolates numbers for Arabic text', () {
    expect(WorkoutFormat.ltr('3×12'), '\u20663×12\u2069');
  });

  test('weight × reps is one isolated unit', () {
    expect(WorkoutFormat.weightTimesReps(52.5, 12), '\u206652.5 × 12\u2069');
  });

  group('units', () {
    LoggedSet s(double w, int r) =>
        LoggedSet(exerciseId: 'x', weight: w, reps: r);

    test('plates: #7×12 ×3', () {
      expect(WorkoutFormat.set(7, 12, ExerciseUnit.plate), '#7×12');
      expect(
        WorkoutFormat.sets([s(7, 12), s(7, 12), s(7, 12)], ExerciseUnit.plate),
        '#7×12 ×3',
      );
      expect(WorkoutFormat.amount(7, ExerciseUnit.plate), '#7');
    });

    test('reps only: no weight anywhere', () {
      expect(WorkoutFormat.set(0, 20, ExerciseUnit.reps), '20');
      expect(
        WorkoutFormat.sets([s(0, 20), s(0, 20)], ExerciseUnit.reps),
        '20 ×2',
      );
      expect(
        WorkoutFormat.sets([s(0, 20), s(0, 18)], ExerciseUnit.reps),
        '20, 18',
      );
      expect(WorkoutFormat.amount(0, ExerciseUnit.reps), '');
    });

    test('kg stays as it was', () {
      expect(WorkoutFormat.set(52.5, 12), '52.5×12');
    });
  });
}
