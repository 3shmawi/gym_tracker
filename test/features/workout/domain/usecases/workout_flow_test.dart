import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/usecases/workout_flow.dart';

void main() {
  const flow = WorkoutFlow();
  final day1 = PlanTemplates.fiveDaySplit.days[0];
  final day2 = PlanTemplates.fiveDaySplit.days[1];

  LoggedSet set(String id, [double w = 20, int r = 12]) =>
      LoggedSet(exerciseId: id, weight: w, reps: r);

  test('day 2 groups the two supersets', () {
    expect(flow.groups(day2), [
      [0],
      [1],
      [2],
      [3],
      [4, 5],
      [6, 7],
    ]);
  });

  test('superset order is A1, B1, A2, B2, A3, B3', () {
    final order = flow.order(day2).where((e) => e.$1 == 4 || e.$1 == 5);
    expect(order, [(4, 1), (5, 1), (4, 2), (5, 2), (4, 3), (5, 3)]);
  });

  test("starts with set 1, at last time's second set (15, 20, 25 → 20)", () {
    final c = flow.next(day1, const [], {
      'flat_db_press': [
        set('flat_db_press', 15),
        set('flat_db_press'),
        set('flat_db_press', 25),
      ],
    })!;
    expect((c.exerciseIndex, c.setNumber), (0, 1));
    expect((c.weight, c.reps), (20, 12));
    expect(c.restAfter, 90);
    expect(c.supersetPartner, isNull);
  });

  test('start weight: one set last time → that set; 0-rep sets ignored', () {
    expect(WorkoutFlow.startWeight([set('pec_deck', 30)]), 30);
    expect(
      WorkoutFlow.startWeight([
        set('pec_deck', 30),
        set('pec_deck', 35, 0),
        set('pec_deck', 32.5),
      ]),
      32.5,
    );
    expect(WorkoutFlow.startWeight(const []), 0);
  });

  test('next set repeats what was just done today', () {
    final c = flow.next(day1, [set('flat_db_press', 25, 10)], const {})!;
    expect((c.exerciseIndex, c.setNumber), (0, 2));
    expect((c.weight, c.reps), (25, 10));
  });

  test('first time with no suggestion starts at 0 kg and target reps', () {
    final c = flow.next(day1, const [], const {})!;
    expect((c.weight, c.reps), (0, 12));
  });

  test('inside a superset: no rest after A, rest after B', () {
    final before = [
      for (final id in [
        'db_shoulder_press',
        'db_front_raise',
        'reverse_pec_deck',
        'db_shrug',
      ])
        for (var i = 0; i < 3; i++) set(id),
    ];
    final a = flow.next(day2, before, const {})!;
    expect((a.exerciseIndex, a.setNumber, a.restAfter), (4, 1, 0));
    expect(a.supersetPartner, 5);

    final b = flow.next(day2, [
      ...before,
      set('alternating_db_curl'),
    ], const {})!;
    expect((b.exerciseIndex, b.setNumber, b.restAfter), (5, 1, 90));
    expect(b.supersetPartner, 4);

    final a2 = flow.next(day2, [
      ...before,
      set('alternating_db_curl'),
      set('cable_kickback'),
    ], const {})!;
    expect((a2.exerciseIndex, a2.setNumber), (4, 2));
  });

  test('done when every planned set is logged', () {
    final all = [
      for (final (i, _) in flow.order(day1)) set(day1.exercises[i].id),
    ];
    expect(flow.next(day1, all, const {}), isNull);
  });

  test('extra sets do not confuse the cursor', () {
    final c = flow.next(day1, [
      for (var i = 0; i < 5; i++) set('flat_db_press'),
    ], const {})!;
    expect(c.exerciseIndex, 1);
  });

  test('sets logged out of order are counted per exercise', () {
    final c = flow.next(day1, [set('pec_deck')], const {})!;
    expect((c.exerciseIndex, c.setNumber), (0, 1));
  });

  group('picked out of order', () {
    test('the picked exercise comes first, at its next set', () {
      final b = day1.exercises[1].id;
      final c = flow.next(
        day1,
        [set(day1.exercises[0].id), set(b)],
        const {},
        focus: b,
      )!;
      expect((c.exerciseIndex, c.setNumber), (1, 2));
      expect(c.weight, 20, reason: "today's last set of it");
    });

    test('finished or unknown picks are ignored', () {
      final a = day1.exercises[0];
      final done = [for (var i = 0; i < a.targetSets; i++) set(a.id)];
      expect(flow.next(day1, done, const {}, focus: a.id)!.exerciseIndex, 1);
      expect(
        flow.next(day1, const [], const {}, focus: '<script>')!.exerciseIndex,
        0,
      );
    });
  });
}
