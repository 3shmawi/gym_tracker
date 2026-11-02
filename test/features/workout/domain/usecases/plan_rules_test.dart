import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/usecases/plan_rules.dart';

const _name = LocalizedName(ar: 'رجل', en: 'Legs');

WorkoutPlan _plan({List<Exercise> exercises = const [], int days = 1}) =>
    WorkoutPlan(
      days: [
        for (var i = 0; i < days; i++)
          WorkoutDay(id: 'd$i', name: _name, exercises: exercises),
      ],
    );

Exercise _ex({
  String id = 'squat',
  int sets = 3,
  int reps = 12,
  int rest = 90,
  double step = 2.5,
  LocalizedName name = _name,
}) => Exercise(
  id: id,
  name: name,
  targetSets: sets,
  targetReps: reps,
  restSeconds: rest,
  weightStep: step,
);

void main() {
  group('PlanNames', () {
    test('trims, joins lines and drops control and direction marks', () {
      expect(PlanNames.clean('  بنش \n\t وضهر  '), 'بنش وضهر');
      expect(PlanNames.clean('Legs\u0000'), 'Legs');
      // A right-to-left override can't flip how the name reads.
      expect(PlanNames.clean('\u202Egel\u202C day'), 'gel day');
      expect(PlanNames.clean('a\u2066b\u2069'), 'a b');
    });

    test('injection-like text is kept as plain text', () {
      for (final hostile in [
        "'; DROP TABLE plan;--",
        '<script>alert(1)</script>',
        r'${process.env}',
        '{"days": []}',
        '../../etc/passwd',
      ]) {
        expect(PlanNames.check(hostile), isNull, reason: hostile);
        expect(PlanNames.from(ar: hostile, en: '')!.ar, hostile);
      }
    });

    test('empty and too long names are refused', () {
      expect(PlanNames.check(''), NameProblem.empty);
      expect(PlanNames.check('   \n '), NameProblem.empty);
      expect(PlanNames.check('', required: false), isNull);
      expect(PlanNames.check('a' * 40), isNull);
      expect(PlanNames.check('a' * 41), NameProblem.tooLong);
      expect(PlanNames.check('ب' * 41), NameProblem.tooLong);
      // Characters as seen: 40 emoji are 40, not 80 UTF-16 units.
      expect(PlanNames.check('💪' * 40), isNull);
    });

    test('one language fills the other', () {
      expect(
        PlanNames.from(ar: 'صدر', en: ''),
        const LocalizedName(ar: 'صدر', en: 'صدر'),
      );
      expect(
        PlanNames.from(ar: ' ', en: 'Chest '),
        const LocalizedName(ar: 'Chest', en: 'Chest'),
      );
      expect(PlanNames.from(ar: '', en: ''), isNull);
      expect(PlanNames.from(ar: 'صدر', en: 'x' * 41), isNull);
    });
  });

  group('validatePlan', () {
    test('the 5-day template is valid', () {
      expect(validatePlan(PlanTemplates.fiveDaySplit), isNull);
    });

    test('a plan needs 1 to 14 days', () {
      expect(validatePlan(const WorkoutPlan(days: [])), isNotNull);
      expect(validatePlan(_plan(days: 14)), isNull);
      expect(validatePlan(_plan(days: 15)), isNotNull);
    });

    test('targets must be in range', () {
      bool ok(Exercise e) => validatePlan(_plan(exercises: [e])) == null;
      expect(ok(_ex()), isTrue);
      expect(ok(_ex(sets: 0)), isFalse);
      expect(ok(_ex(sets: 1)), isTrue);
      expect(ok(_ex(sets: 10)), isTrue);
      expect(ok(_ex(sets: 11)), isFalse);
      expect(ok(_ex(reps: 0)), isFalse);
      expect(ok(_ex(reps: 100)), isTrue);
      expect(ok(_ex(reps: 101)), isFalse);
      expect(ok(_ex(rest: -1)), isFalse);
      expect(ok(_ex(rest: 0)), isTrue);
      expect(ok(_ex(rest: 600)), isTrue);
      expect(ok(_ex(rest: 601)), isFalse);
      expect(ok(_ex(step: 0)), isFalse);
      expect(ok(_ex(step: -2.5)), isFalse);
      expect(ok(_ex(step: double.nan)), isFalse);
      expect(ok(_ex(step: double.infinity)), isFalse);
      expect(ok(_ex(step: 0.25)), isTrue);
      expect(ok(_ex(step: 51)), isFalse);
    });

    test('names must be clean and short', () {
      bool ok(LocalizedName n) =>
          validatePlan(_plan(exercises: [_ex(name: n)])) == null;
      expect(ok(const LocalizedName(ar: '', en: 'x')), isFalse);
      expect(ok(LocalizedName(ar: 'x', en: 'y' * 41)), isFalse);
      expect(ok(const LocalizedName(ar: 'a\nb', en: 'x')), isFalse);
      expect(ok(const LocalizedName(ar: ' a', en: 'x')), isFalse);
      expect(
        validatePlan(
          const WorkoutPlan(
            days: [
              WorkoutDay(
                id: 'd',
                name: LocalizedName(ar: '', en: ''),
                exercises: [],
              ),
            ],
          ),
        ),
        isNotNull,
      );
    });

    test('ids must be present and not repeat', () {
      expect(
        validatePlan(
          _plan(
            exercises: [
              _ex(id: 'a'),
              _ex(id: 'a'),
            ],
          ),
        ),
        isNotNull,
      );
      expect(validatePlan(_plan(exercises: [_ex(id: '')])), isNotNull);
      expect(
        validatePlan(
          const WorkoutPlan(
            days: [
              WorkoutDay(id: 'd', name: _name, exercises: []),
              WorkoutDay(id: 'd', name: _name, exercises: []),
            ],
          ),
        ),
        isNotNull,
      );
      // The same exercise on two days (day 1 and day 4) is fine.
      expect(validatePlan(_plan(exercises: [_ex()], days: 2)), isNull);
    });

    test('at most 30 exercises a day', () {
      expect(
        validatePlan(
          _plan(exercises: [for (var i = 0; i < 30; i++) _ex(id: 'e$i')]),
        ),
        isNull,
      );
      expect(
        validatePlan(
          _plan(exercises: [for (var i = 0; i < 31; i++) _ex(id: 'e$i')]),
        ),
        isNotNull,
      );
    });
  });

  group('newPlanId', () {
    final now = DateTime.utc(2026, 11, 1, 19);

    test('prefix plus the time', () {
      final id = newPlanId('ex', const {}, now);
      expect(id, startsWith('ex-'));
      expect(id, 'ex-${now.microsecondsSinceEpoch.toRadixString(36)}');
    });

    test('never repeats a taken id', () {
      final taken = <String>{};
      for (var i = 0; i < 5; i++) {
        taken.add(newPlanId('ex', taken, now));
      }
      expect(taken, hasLength(5));
    });

    test('new exercises get the editor defaults', () {
      const e = Exercise(id: 'x', name: _name);
      expect(e.targetSets, PlanLimits.newSets);
      expect(e.targetReps, PlanLimits.newReps);
      expect(e.restSeconds, PlanLimits.newRest);
      expect(e.weightStep, PlanLimits.newWeightStep);
    });
  });
}
