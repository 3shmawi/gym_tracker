// Rep ranges with double progression (docs/designs/rep_ranges.md).
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/workout/domain/entities/next_workout.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/usecases/edit_plan.dart';
import 'package:gym_tracker/features/workout/domain/usecases/plan_rules.dart';
import 'package:gym_tracker/features/workout/domain/usecases/suggest_weight.dart';
import 'package:gym_tracker/features/workout/domain/usecases/working_sets.dart';
import 'package:gym_tracker/features/workout/domain/usecases/workout_flow.dart';

const _name = LocalizedName(ar: 'بار مستوي', en: 'Bench');

/// 2 sets, 6–10, step 2.5: the coach's program from the field test.
const bench = Exercise(
  id: 'bench',
  name: _name,
  targetSets: 2,
  targetReps: 6,
  repsTop: 10,
);

List<LoggedSet> sets(List<(double, int)> s, [String id = 'bench']) => [
  for (final (w, r) in s) LoggedSet(exerciseId: id, weight: w, reps: r),
];

WorkoutPlan planOf(Exercise e) => WorkoutPlan(
  days: [
    WorkoutDay(id: 'd', name: _name, exercises: [e]),
  ],
);

void main() {
  group('Exercise JSON', () {
    test('a range round-trips as "top"', () {
      final json = bench.toJson();
      expect(json['top'], 10);
      expect(Exercise.fromJson(json), bench);
    });

    test('no range: no key, so the plan is what it was before 0024', () {
      final json = bench.withRange(null).toJson();
      expect(json.containsKey('top'), isFalse);
      expect(Exercise.fromJson(json).repsTop, isNull);
    });

    test('a wrong type throws, like a bad reps', () {
      for (final bad in <Object>['10', 10.5, true, <String, Object>{}]) {
        final json = {...bench.toJson(), 'top': bad};
        expect(() => Exercise.fromJson(json), throwsA(isA<TypeError>()));
      }
    });

    test('equality and hash include the range', () {
      expect(bench == bench.withRange(12), isFalse);
      expect(bench.hashCode == bench.withRange(10).hashCode, isTrue);
      expect(bench.copyWith(targetSets: 3).repsTop, 10, reason: 'kept');
    });
  });

  group('validatePlan', () {
    test('top from reps to 100', () {
      expect(validatePlan(planOf(bench)), isNull);
      expect(validatePlan(planOf(bench.withRange(6))), isNull);
      expect(validatePlan(planOf(bench.withRange(5))), 'top out of range');
      expect(validatePlan(planOf(bench.withRange(101))), 'top out of range');
    });
  });

  group('EditPlan', () {
    const edit = EditPlan();
    Exercise only(WorkoutPlan p) => p.days.single.exercises.single;

    test('setRange turns it on, clamps it, and null turns it off', () {
      final fixed = planOf(bench.withRange(null));
      expect(only(edit.setRange(fixed, 'd', 'bench', top: 10)).repsTop, 10);
      expect(only(edit.setRange(fixed, 'd', 'bench', top: 2)).repsTop, 6);
      expect(only(edit.setRange(fixed, 'd', 'bench', top: 500)).repsTop, 100);
      expect(
        only(edit.setRange(planOf(bench), 'd', 'bench', top: null)).repsTop,
        isNull,
      );
    });

    test('raising reps above the top raises the top; lowering keeps it', () {
      final p = planOf(bench);
      final up = only(edit.setTargets(p, 'd', 'bench', reps: 12));
      expect((up.targetReps, up.repsTop), (12, 12));
      final down = only(edit.setTargets(p, 'd', 'bench', reps: 4));
      expect((down.targetReps, down.repsTop), (4, 10));
      expect(only(edit.setTargets(p, 'd', 'bench', sets: 3)).repsTop, 10);
    });

    test('a locked day refuses the range too', () {
      expect(
        () => edit.setRange(
          planOf(bench),
          'd',
          'bench',
          top: 12,
          lockedDayId: 'd',
        ),
        throwsA(isA<PlanEditException>()),
      );
    });

    test('the default top is the reps + 4', () {
      expect(EditPlan.defaultRangeWidth, 4);
    });
  });

  group('workingSets', () {
    test('the sets at the heaviest weight, in order; 0 reps ignored', () {
      expect(
        workingSets(sets([(20, 12), (35, 7), (35, 0), (35, 6), (30, 8)])),
        sets([(35, 7), (35, 6)]),
      );
      expect(workingSets(const []), isEmpty);
      expect(workingSets(sets([(35, 0)])), isEmpty);
    });
  });

  group('SuggestWeight with a range (the spec table)', () {
    const suggest = SuggestWeight();
    const keep35 = WeightSuggestion(weight: 35, trend: Trend.keep);
    const up = WeightSuggestion(weight: 37.5, trend: Trend.up);

    final table = <String, (Exercise, List<(double, int)>, WeightSuggestion)>{
      'best set reached the bottom': (bench, [(35, 6), (35, 5)], keep35),
      'climbing inside the range': (bench, [(35, 10), (35, 9)], keep35),
      'every set at the top': (bench, [(35, 10), (35, 10)], up),
      'more sets than planned, all at the top': (
        bench,
        [(35, 10), (35, 10), (35, 10)],
        up,
      ),
      'one set only (fewer than planned)': (bench, [(35, 10)], keep35),
      'every set below the bottom': (
        bench,
        [(35, 5), (35, 4)],
        const WeightSuggestion(weight: 32.5, trend: Trend.down),
      ),
      'a warm-up is not a working set': (
        bench,
        [(20, 12), (35, 7), (35, 6)],
        keep35,
      ),
      'a lighter set 2 is not a working set': (
        bench,
        [(37.5, 6), (35, 8)],
        const WeightSuggestion(weight: 37.5, trend: Trend.keep),
      ),
      'top equal to the bottom': (
        bench.withRange(6).copyWith(targetReps: 8).withRange(8),
        [(35, 8), (35, 8)],
        up,
      ),
      'reps only at the top: up with weight 0': (
        bench.copyWith(unit: ExerciseUnit.reps),
        [(0, 10), (0, 10)],
        const WeightSuggestion(weight: 0, trend: Trend.up),
      ),
      'never below 0': (
        bench,
        [(2.5, 3), (2.5, 2)],
        const WeightSuggestion(weight: 0, trend: Trend.down),
      ),
    };
    for (final MapEntry(key: label, value: (e, last, want)) in table.entries) {
      test(label, () => expect(suggest(e, sets(last)), want));
    }

    test('no history: first time', () {
      expect(suggest(bench, const []).trend, Trend.firstTime);
    });

    test('the same sets with a fixed target 6 still use the old rule', () {
      // 35×6, 35×6 against a fixed 6 is "every rep hit" → up; with 6–10 it
      // is a keep. This is the field-test bug the range fixes.
      final fixed = bench.withRange(null);
      expect(suggest(fixed, sets([(35, 6), (35, 6)])).trend, Trend.up);
      expect(suggest(bench, sets([(35, 6), (35, 6)])).trend, Trend.keep);
    });
  });

  group('WorkoutFlow pre-fill with a range', () {
    const flow = WorkoutFlow();
    const day = WorkoutDay(id: 'd', name: _name, exercises: [bench]);
    final last = {
      'bench': sets([(20, 12), (35, 8), (35, 6)]),
    };
    const keep = {'bench': WeightSuggestion(weight: 35, trend: Trend.keep)};

    test('set 1: the suggested weight and last time set 1 reps', () {
      final c = flow.next(day, const [], last, suggestions: keep)!;
      expect((c.weight, c.reps), (35.0, 8));
    });

    test('set 2: today set 1 weight, last time set 2 reps (not today)', () {
      final c = flow.next(day, sets([(35, 9)]), last, suggestions: keep)!;
      expect((c.setNumber, c.weight, c.reps), (2, 35.0, 6));
    });

    test('after up: the new weight starts at the bottom', () {
      final c = flow.next(
        day,
        const [],
        last,
        suggestions: const {
          'bench': WeightSuggestion(weight: 37.5, trend: Trend.up),
        },
      )!;
      expect((c.weight, c.reps), (37.5, 6));
    });

    test('after down: the bottom too', () {
      final c = flow.next(
        day,
        const [],
        last,
        suggestions: const {
          'bench': WeightSuggestion(weight: 32.5, trend: Trend.down),
        },
      )!;
      expect((c.weight, c.reps), (32.5, 6));
    });

    test('the member moved the weight today: the bottom', () {
      final c = flow.next(day, sets([(40, 6)]), last, suggestions: keep)!;
      expect((c.weight, c.reps), (40.0, 6));
    });

    test('no history: the bottom, weight from startWeight (0)', () {
      final c = flow.next(day, const [], const {})!;
      expect((c.weight, c.reps), (0.0, 6));
    });

    test('more sets today than last time: the bottom', () {
      expect(
        WorkoutFlow.rangeReps(bench, sets([(35, 8)]), setNumber: 2, weight: 35),
        6,
      );
    });

    test('reps only after up keeps last time reps (weight stays 0)', () {
      final pullUps = bench.copyWith(unit: ExerciseUnit.reps);
      final c = flow.next(
        WorkoutDay(id: 'd', name: _name, exercises: [pullUps]),
        const [],
        {
          'bench': sets([(0, 10), (0, 10)]),
        },
        suggestions: const {
          'bench': WeightSuggestion(weight: 0, trend: Trend.up),
        },
      )!;
      expect((c.weight, c.reps), (0.0, 10));
    });

    test('a fixed target keeps today rules (suggestion ignored)', () {
      final fixed = bench.withRange(null);
      final c = flow.next(
        WorkoutDay(id: 'd', name: _name, exercises: [fixed]),
        const [],
        last,
        suggestions: const {
          'bench': WeightSuggestion(weight: 99, trend: Trend.up),
        },
      )!;
      expect((c.weight, c.reps), (35.0, 6), reason: 'startWeight, target');
    });
  });
}
