import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/library/data/catalog_exercise_library.dart';
import 'package:gym_tracker/features/library/data/exercise_catalog.dart';
import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/usecases/plan_rules.dart';

void main() {
  const all = ExerciseCatalog.all;
  final idPattern = RegExp(r'^[a-z0-9_-]{1,64}$');

  group('the seed matches PlanTemplates, so history stays matched', () {
    final templateExercises = <String, Exercise>{
      for (final day in PlanTemplates.fiveDaySplit.days)
        for (final e in day.exercises) e.id: e,
    };

    test('every template exercise is in the library', () {
      final ids = {for (final e in all) e.id};
      expect(ids, containsAll(templateExercises.keys));
      expect(templateExercises, hasLength(23));
    });

    test('same id, names and starting targets', () {
      for (final lib in all) {
        final t = templateExercises[lib.id];
        if (t == null) continue;
        final d = lib.defaults;
        expect(d.name.en, t.name.en, reason: lib.id);
        expect(d.name.ar, t.name.ar, reason: lib.id);
        expect(d.targetSets, t.targetSets, reason: lib.id);
        expect(d.targetReps, t.targetReps, reason: lib.id);
        expect(d.restSeconds, t.restSeconds, reason: lib.id);
        expect(d.weightStep, t.weightStep, reason: lib.id);
        expect(d.supersetWithNext, t.supersetWithNext, reason: lib.id);
      }
    });
  });

  group('every entry is well formed', () {
    test('ids are unique and safe (they go in plans, history and URLs)', () {
      final ids = all.map((e) => e.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      for (final id in ids) {
        expect(idPattern.hasMatch(id), isTrue, reason: id);
      }
    });

    test('names are clean, both languages, within the plan limits', () {
      for (final e in all) {
        expect(PlanNames.check(e.name.en), isNull, reason: e.id);
        expect(PlanNames.check(e.name.ar), isNull, reason: e.id);
        expect(PlanNames.clean(e.name.en), e.name.en, reason: e.id);
        expect(PlanNames.clean(e.name.ar), e.name.ar, reason: e.id);
      }
    });

    test('2-3 short steps in both languages, no markup or links', () {
      for (final e in all) {
        expect(
          e.steps.length,
          inInclusiveRange(LibraryExercise.minSteps, LibraryExercise.maxSteps),
          reason: e.id,
        );
        for (final step in e.steps) {
          for (final text in [step.ar, step.en]) {
            expect(text.trim(), isNotEmpty, reason: e.id);
            expect(
              text.runes.length,
              lessThanOrEqualTo(LibraryExercise.maxStepLength),
              reason: '${e.id}: $text',
            );
            expect(text, isNot(matches(RegExp(r'[<>]|https?:|www\.'))));
            expect(PlanNames.clean(text), text, reason: e.id);
          }
        }
      }
    });

    test('at least one piece of equipment (or none needed), no repeats', () {
      for (final e in all) {
        expect(e.equipment, isNotEmpty, reason: e.id);
        expect(e.equipment.toSet(), hasLength(e.equipment.length));
        if (e.equipment.contains(Equipment.bodyweight)) {
          expect(e.equipment, hasLength(1), reason: e.id);
        }
      }
    });

    test('starting targets are inside the plan limits', () {
      final plan = WorkoutPlan(
        days: [
          WorkoutDay(
            id: 'd1',
            name: const LocalizedName(ar: 'ا', en: 'A'),
            exercises: [for (final e in all) e.defaults],
          ),
        ],
      );
      expect(validatePlan(plan), isNull);
    });

    test('every muscle group has exercises', () {
      for (final m in MuscleGroup.values) {
        expect(all.where((e) => e.muscle == m), isNotEmpty, reason: m.name);
      }
    });
  });

  test('byId finds an exercise and answers null for anything else', () {
    final lib = CatalogExerciseLibrary();
    expect(lib.byId('flat_db_press')?.muscle, MuscleGroup.chest);
    for (final id in ['', 'nope', '../x', "'; DROP TABLE", 'FLAT_DB_PRESS']) {
      expect(lib.byId(id), isNull, reason: id);
    }
    expect(() => lib.all.add(all.first), throwsUnsupportedError);
  });
}
