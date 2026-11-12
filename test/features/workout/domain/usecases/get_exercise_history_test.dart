import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/usecases/get_exercise_history.dart';

const WorkoutPlan _plan = PlanTemplates.fiveDaySplit;
const _press = 'flat_db_press';

WorkoutSession _session(int day, DateTime at, List<(String, double, int)> s) =>
    WorkoutSession(
      dayId: legacyDayId(day),
      finishedAt: at,
      sets: [
        for (final (id, w, r) in s)
          LoggedSet(exerciseId: id, weight: w, reps: r),
      ],
    );

void main() {
  const get = GetExerciseHistory();

  final history = [
    // Out of order on purpose: newest first in storage must not matter.
    _session(0, DateTime(2026, 10, 27), [
      (_press, 25, 12),
      (_press, 25, 10),
      ('wide_lat_pulldown', 50, 12),
    ]),
    _session(0, DateTime(2026, 10, 13), [(_press, 20, 12), (_press, 20, 12)]),
    _session(0, DateTime(2026, 10, 20), [
      (_press, 22.5, 12),
      (_press, 22.5, 0),
    ]),
    _session(1, DateTime(2026, 10, 21), [('db_shoulder_press', 10, 12)]),
  ];

  test('every time, newest first, with the change from the time before', () {
    final h = get(_plan, history, _press)!;
    expect(h.exercise.id, _press);
    expect([for (final e in h.entries) e.date.day], [27, 20, 13]);
    expect([for (final e in h.entries) e.change], [2.5, 2.5, null]);
    expect(h.entries.first.sets.map((s) => s.reps), [12, 10]);
  });

  test('the plan days it is on, in plan order', () {
    // Abs is on day 1 and day 4.
    final abs = get(_plan, history, 'abs')!;
    expect(abs.days.map((d) => d.number), [1, 4]);
    expect(abs.days.first.name.en, 'Chest & Back');
    expect(get(_plan, history, _press)!.days.map((d) => d.number), [1]);
    final squat = get(_plan, history, 'barbell_squat')!;
    expect(squat.days.map((d) => d.number), [3]);
    expect(squat.days.single.name.ar, 'رجل');
  });

  test('sets with 0 reps are left out', () {
    final h = get(_plan, history, _press)!;
    expect(h.entries[1].sets, hasLength(1));
  });

  test('progress: first → latest heaviest, best set, workouts', () {
    final p = get(_plan, history, _press)!.progress;
    expect(p.first!.topWeight, 20);
    expect(p.latest!.topWeight, 25);
    expect(p.gain, 5);
    expect(p.best, const LoggedSet(exerciseId: _press, weight: 25, reps: 12));
    expect(p.workouts, 3);
  });

  test('a lighter time shows a negative change', () {
    final h = get(_plan, [
      ...history,
      _session(0, DateTime(2026, 11, 3), [(_press, 22.5, 12)]),
    ], _press)!;
    expect(h.entries.first.change, -2.5);
    expect(h.progress.gain, 2.5);
  });

  test('never done: no entries, no gain', () {
    final h = get(_plan, history, 'pec_deck')!;
    expect(h.entries, isEmpty);
    expect(h.progress.started, isFalse);
    expect(h.progress.gain, isNull);
  });

  test('ids that are not in the plan give null, never a crash', () {
    for (final id in [
      '',
      'nope',
      "x'; DROP TABLE s;--",
      '../settings',
      'a' * 5000,
    ]) {
      expect(get(_plan, history, id), isNull, reason: id);
    }
  });

  test('overview: every plan exercise once, in plan order', () {
    final all = get.overview(_plan, history);
    final ids = [for (final p in all) p.exercise.id];
    expect(ids.toSet().length, ids.length, reason: 'no duplicates');
    expect(ids.first, _press);
    expect(all.first.gain, 5);
    expect(all.where((p) => p.started).length, 3);
  });

  test('no history: nothing started', () {
    expect(get.overview(_plan, const []).every((p) => !p.started), isTrue);
  });
}
