import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/usecases/edit_plan.dart';
import 'package:gym_tracker/features/workout/domain/usecases/get_next_workout.dart';
import 'package:gym_tracker/features/workout/domain/usecases/plan_rules.dart';

const edit = EditPlan();
const keep = KeepNextWorkout();
const getNext = GetNextWorkout();

LocalizedName n(String en) => LocalizedName(ar: en, en: en);

Exercise ex(String id, {bool superset = false}) =>
    Exercise(id: id, name: n(id), supersetWithNext: superset);

WorkoutDay day(String id, [List<Exercise> exercises = const []]) =>
    WorkoutDay(id: id, name: n(id), exercises: exercises);

final plan = WorkoutPlan(
  days: [
    day('a', [ex('a1'), ex('a2', superset: true), ex('a3')]),
    day('b', [ex('b1')]),
    day('c', [ex('c1')]),
  ],
);

List<String> ids(WorkoutPlan p) => [for (final d in p.days) d.id];
List<String> exIds(WorkoutPlan p, String dayId) => [
  for (final e in p.dayById(dayId)!.exercises) e.id,
];

Matcher refused(PlanEditError reason) =>
    throwsA(isA<PlanEditException>().having((e) => e.reason, 'reason', reason));

WorkoutSession done(String dayId, DateTime at) =>
    WorkoutSession(dayId: dayId, finishedAt: at, sets: const []);

void main() {
  group('days', () {
    test('add, rename, delete, move', () {
      var p = edit.addDay(plan, n('d'), id: 'd');
      expect(ids(p), ['a', 'b', 'c', 'd']);
      expect(p.dayById('d')!.exercises, isEmpty);
      p = edit.renameDay(p, 'b', const LocalizedName(ar: 'ضهر', en: 'Back'));
      expect(p.dayById('b')!.name.en, 'Back');
      p = edit.deleteDay(p, 'a');
      expect(ids(p), ['b', 'c', 'd']);
      p = edit.moveDay(p, 2, 0);
      expect(ids(p), ['d', 'b', 'c']);
      p = edit.moveDay(p, 0, 2);
      expect(ids(p), ['b', 'c', 'd']);
    });

    test('the last day stays', () {
      final one = WorkoutPlan(days: [day('a')]);
      expect(() => edit.deleteDay(one, 'a'), refused(PlanEditError.lastDay));
    });

    test('at most 14 days', () {
      var p = WorkoutPlan(days: [day('x')]);
      for (var i = 0; i < 13; i++) {
        p = edit.addDay(p, n('d$i'), id: 'd$i');
      }
      expect(
        () => edit.addDay(p, n('extra'), id: 'extra'),
        refused(PlanEditError.tooMany),
      );
    });

    test('unknown ids and bad positions are refused', () {
      expect(() => edit.deleteDay(plan, 'zz'), refused(PlanEditError.notFound));
      expect(
        () => edit.renameDay(plan, 'zz', n('x')),
        refused(PlanEditError.notFound),
      );
      expect(() => edit.moveDay(plan, 0, 3), refused(PlanEditError.notFound));
      expect(() => edit.moveDay(plan, -1, 0), refused(PlanEditError.notFound));
    });

    test('invalid names are refused', () {
      for (final bad in [
        const LocalizedName(ar: '', en: ''),
        LocalizedName(ar: 'x' * 41, en: 'x'),
        const LocalizedName(ar: 'a\nb', en: 'x'),
      ]) {
        expect(
          () => edit.addDay(plan, bad, id: 'd'),
          refused(PlanEditError.invalidName),
        );
        expect(
          () => edit.renameDay(plan, 'a', bad),
          refused(PlanEditError.invalidName),
        );
      }
    });
  });

  group('exercises', () {
    test('add with the default targets, rename, delete, move', () {
      var p = edit.addExercise(plan, 'b', n('b2'), id: 'b2');
      final added = p.dayById('b')!.exercises.last;
      expect(added.id, 'b2');
      expect(added.targetSets, PlanLimits.newSets);
      expect(added.targetReps, PlanLimits.newReps);
      p = edit.renameExercise(p, 'b', 'b2', n('Row'));
      expect(p.dayById('b')!.exercises.last.name.en, 'Row');
      p = edit.moveExercise(p, 'b', 1, 0);
      expect(exIds(p, 'b'), ['b2', 'b1']);
      p = edit.deleteExercise(p, 'b', 'b1');
      expect(exIds(p, 'b'), ['b2']);
      // Ids stay with the exercise: renaming keeps its history.
      expect(p.dayById('b')!.exercises.single.id, 'b2');
    });

    test('superset with the next one; the last exercise never keeps it', () {
      var p = edit.setSuperset(plan, 'a', 'a1', withNext: true);
      expect(p.dayById('a')!.exercises.first.supersetWithNext, isTrue);
      p = edit.setSuperset(p, 'a', 'a3', withNext: true);
      expect(p.dayById('a')!.exercises.last.supersetWithNext, isFalse);
      // Deleting the partner after it ends the superset.
      p = edit.deleteExercise(plan, 'a', 'a3');
      expect(p.dayById('a')!.exercises.last.supersetWithNext, isFalse);
      // Moving it to the end ends it too.
      p = edit.moveExercise(plan, 'a', 1, 2);
      expect(exIds(p, 'a'), ['a1', 'a3', 'a2']);
      expect(p.dayById('a')!.exercises.last.supersetWithNext, isFalse);
    });

    test('targets are clamped to the limits', () {
      Exercise after({int? sets, int? reps, int? rest}) => edit
          .setTargets(
            plan,
            'b',
            'b1',
            sets: sets,
            reps: reps,
            restSeconds: rest,
          )
          .dayById('b')!
          .exercises
          .single;
      expect(after(sets: 0).targetSets, 1);
      expect(after(sets: 99).targetSets, 10);
      expect(after(reps: -5).targetReps, 1);
      expect(after(reps: 1000).targetReps, 100);
      expect(after(rest: -1).restSeconds, 0);
      expect(after(rest: 9999).restSeconds, 600);
      expect(after(sets: 4).targetSets, 4);
      // Untouched targets stay.
      expect(after(sets: 4).targetReps, 12);
    });

    test('a weight step must be a number above 0', () {
      expect(
        edit
            .setTargets(plan, 'b', 'b1', weightStep: 1.25)
            .dayById('b')!
            .exercises
            .single
            .weightStep,
        1.25,
      );
      for (final bad in [0.0, -1.0, double.nan, double.infinity, 51.0]) {
        expect(
          () => edit.setTargets(plan, 'b', 'b1', weightStep: bad),
          throwsA(isA<PlanEditException>()),
          reason: '$bad',
        );
      }
    });

    test('at most 30 exercises a day', () {
      var p = WorkoutPlan(days: [day('a')]);
      for (var i = 0; i < 30; i++) {
        p = edit.addExercise(p, 'a', n('e$i'), id: 'e$i');
      }
      expect(
        () => edit.addExercise(p, 'a', n('x'), id: 'x'),
        refused(PlanEditError.tooMany),
      );
    });

    test('unknown exercises are refused', () {
      expect(
        () => edit.deleteExercise(plan, 'a', 'nope'),
        refused(PlanEditError.notFound),
      );
      expect(
        () => edit.setTargets(plan, 'a', 'nope', sets: 3),
        refused(PlanEditError.notFound),
      );
    });
  });

  group('adding an exercise of the library', () {
    const squat = Exercise(
      id: 'barbell_squat',
      name: LocalizedName(ar: 'بار اسكوات حر', en: 'Barbell Back Squat'),
      weightStep: 5,
      restSeconds: 120,
    );

    test('keeps its id, name and starting targets', () {
      final p = edit.addLibraryExercise(plan, 'b', squat);
      expect(exIds(p, 'b'), ['b1', 'barbell_squat']);
      final added = p.dayById('b')!.exercises.last;
      expect(added.restSeconds, 120);
      expect(added.weightStep, 5);
      expect(added.name.en, 'Barbell Back Squat');
      expect(validatePlan(p), isNull);
    });

    test('the same exercise may be in two days, not twice in one', () {
      final p = edit.addLibraryExercise(plan, 'b', squat);
      final both = edit.addLibraryExercise(p, 'c', squat);
      expect(exIds(both, 'c'), ['c1', 'barbell_squat']);
      expect(
        () => edit.addLibraryExercise(p, 'b', squat),
        refused(PlanEditError.duplicate),
      );
    });

    test('a full day, a locked day and an unknown day are refused', () {
      var p = plan;
      for (var i = 0; i < PlanLimits.maxExercisesPerDay - 1; i++) {
        p = edit.addExercise(p, 'b', n('e$i'), id: 'e$i');
      }
      expect(
        () => edit.addLibraryExercise(p, 'b', squat),
        refused(PlanEditError.tooMany),
      );
      expect(
        () => edit.addLibraryExercise(plan, 'a', squat, lockedDayId: 'a'),
        refused(PlanEditError.lockedDay),
      );
      expect(
        () => edit.addLibraryExercise(plan, 'zzz', squat),
        refused(PlanEditError.notFound),
      );
    });

    test('an old workout of the exercise is matched again by its id', () {
      // History written before: the same id.
      final history = [
        WorkoutSession(
          dayId: 'b',
          finishedAt: DateTime(2026, 10),
          sets: const [
            LoggedSet(exerciseId: 'barbell_squat', weight: 100, reps: 5),
          ],
        ),
      ];
      final p = edit.addLibraryExercise(plan, 'b', squat);
      final taken = takenIds(p, history);
      expect(taken, contains('barbell_squat'));
      expect(
        history.single.sets.single.exerciseId,
        p.dayById('b')!.exercises.last.id,
      );
    });
  });

  group('the day of the workout in progress is locked', () {
    test('no rename, delete or exercise changes', () {
      void locked(WorkoutPlan Function() change) =>
          expect(change, refused(PlanEditError.lockedDay));
      locked(() => edit.renameDay(plan, 'a', n('x'), lockedDayId: 'a'));
      locked(() => edit.deleteDay(plan, 'a', lockedDayId: 'a'));
      locked(
        () => edit.addExercise(plan, 'a', n('x'), id: 'x', lockedDayId: 'a'),
      );
      locked(() => edit.deleteExercise(plan, 'a', 'a1', lockedDayId: 'a'));
      locked(() => edit.moveExercise(plan, 'a', 0, 1, lockedDayId: 'a'));
      locked(() => edit.setTargets(plan, 'a', 'a1', sets: 5, lockedDayId: 'a'));
      locked(
        () =>
            edit.setSuperset(plan, 'a', 'a1', withNext: true, lockedDayId: 'a'),
      );
    });

    test('other days stay editable and the locked day can move', () {
      final p = edit.deleteDay(plan, 'b', lockedDayId: 'a');
      expect(ids(p), ['a', 'c']);
      expect(ids(edit.moveDay(plan, 0, 2)), ['b', 'c', 'a']);
    });
  });

  group('KeepNextWorkout: the waiting workout stays the same', () {
    final now = DateTime(2026, 11, 10);
    // Finished day a: b is next.
    final history = [done('a', DateTime(2026, 11, 9, 19))];

    String nextAfter(WorkoutPlan after, ChosenDay? chosen) =>
        getNext(after, history, now: now, chosenDay: chosen).day.id;

    test('renaming or adding days changes nothing', () {
      final after = edit.addDay(plan, n('d'), id: 'd');
      expect(
        keep(
          before: plan,
          after: after,
          history: history,
          chosen: null,
          now: now,
        ),
        isNull,
      );
    });

    test('reordering pins the day that was waiting', () {
      // c moves between a and b: the history alone would now say c.
      final after = edit.moveDay(plan, 2, 1);
      final chosen = keep(
        before: plan,
        after: after,
        history: history,
        chosen: null,
        now: now,
      );
      expect(chosen, const ChosenDay('b', byEdit: true));
      expect(nextAfter(after, chosen), 'b');
    });

    test('deleting the waiting day: the one after it waits', () {
      final after = edit.deleteDay(plan, 'b');
      final chosen = keep(
        before: plan,
        after: after,
        history: history,
        chosen: null,
        now: now,
      );
      // a → c is what the history says anyway.
      expect(chosen, isNull);
      expect(nextAfter(after, chosen), 'c');
    });

    test('deleting the last finished day keeps the waiting one', () {
      final after = edit.deleteDay(plan, 'a');
      final chosen = keep(
        before: plan,
        after: after,
        history: history,
        chosen: null,
        now: now,
      );
      expect(nextAfter(after, chosen), 'b');
    });

    test("the member's own choice holds while its day exists", () {
      const mine = ChosenDay('c');
      final after = edit.moveDay(plan, 2, 0);
      expect(
        keep(
          before: plan,
          after: after,
          history: history,
          chosen: mine,
          now: now,
        ),
        mine,
      );
      final deleted = edit.deleteDay(plan, 'c');
      final chosen = keep(
        before: plan,
        after: deleted,
        history: history,
        chosen: mine,
        now: now,
      );
      // c is gone: the day after it (wrapping) waits.
      expect(nextAfter(deleted, chosen), 'a');
    });

    test('a pin from an edit keeps the waiting banner', () {
      final after = edit.moveDay(plan, 2, 1);
      final chosen = keep(
        before: plan,
        after: after,
        history: history,
        chosen: null,
        now: now,
      );
      final next = getNext(after, history, now: now, chosenDay: chosen);
      expect(next.day.id, 'b');
      // Due on the 10th (the day after the 9th) → not waiting yet; two
      // days later it is.
      final later = getNext(
        after,
        history,
        now: DateTime(2026, 11, 12),
        chosenDay: chosen,
      );
      expect(later.waitingSince, DateTime(2026, 11, 10));
    });

    test('a brand-new plan has nothing to keep', () {
      expect(
        keep(
          before: null,
          after: plan,
          history: const [],
          chosen: null,
          now: now,
        ),
        isNull,
      );
    });

    test('the template keeps working with migrated history', () {
      // History saved before day ids: day 0 → day-1.
      final old = WorkoutSession.fromJson(const {
        'day': 0,
        'finished_at': '2026-11-09T17:00:00.000Z',
        'sets': <Object?>[],
      });
      final next = getNext(PlanTemplates.fiveDaySplit, [old], now: now);
      expect(next.dayIndex, 1);
    });
  });

  test('takenIds covers the plan and the history', () {
    final taken = takenIds(plan, [
      WorkoutSession(
        dayId: 'gone-day',
        finishedAt: DateTime.utc(2026),
        sets: const [LoggedSet(exerciseId: 'gone-ex', weight: 10, reps: 5)],
      ),
    ]);
    expect(
      taken,
      containsAll(['a', 'b', 'c', 'a1', 'b1', 'gone-day', 'gone-ex']),
    );
  });
}
