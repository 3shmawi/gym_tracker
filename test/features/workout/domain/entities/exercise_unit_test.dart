import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';

void main() {
  const name = LocalizedName(ar: 'جهاز', en: 'Machine');
  Map<String, Object?> json([Object? unit = const _Missing()]) => {
    'id': 'e1',
    'name': name.toJson(),
    'sets': 3,
    'reps': 12,
    'rest': 90,
    'step': 2.5,
    'superset': false,
    if (unit is! _Missing) 'unit': unit,
  };

  test('a plan saved before units reads as kg', () {
    expect(Exercise.fromJson(json()).unit, ExerciseUnit.kg);
  });

  test('plate and reps round-trip', () {
    for (final unit in [ExerciseUnit.plate, ExerciseUnit.reps]) {
      final e = Exercise.fromJson(json(unit.name));
      expect(e.unit, unit);
      expect(Exercise.fromJson(e.toJson()), e);
    }
  });

  test('kg is not written: a kg plan is byte-for-byte what it was', () {
    final e = Exercise.fromJson(json('kg'));
    expect(e.toJson().containsKey('unit'), isFalse);
  });

  test('unknown or hostile values fall back to kg, never throw', () {
    for (final v in ['lb', 'KG', '', 42, null, true, "kg'; drop table --"]) {
      expect(Exercise.fromJson(json(v)).unit, ExerciseUnit.kg, reason: '$v');
    }
  });

  test('step: kg uses the machine step, plates 1, reps none', () {
    const e = Exercise(id: 'e', name: name, weightStep: 5);
    expect(e.step, 5);
    expect(e.copyWith(unit: ExerciseUnit.plate).step, 1);
    expect(e.copyWith(unit: ExerciseUnit.reps).step, 0);
  });
}

class _Missing {
  const new();
}
