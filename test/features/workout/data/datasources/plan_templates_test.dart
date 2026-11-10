import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';

/// The member's real plan. Change it only when their plan changes.
void main() {
  const plan = PlanTemplates.fiveDaySplit;
  List<String> ar(int day) => [
    for (final e in plan.days[day].exercises) e.name.ar,
  ];

  test('5 days in the right order', () {
    expect(
      [for (final d in plan.days) d.name.ar],
      ['بنش وضهر', 'كتف ودراع', 'رجل', 'بنش وضهر', 'كتف ودراع'],
    );
  });

  test('day 2: shoulders, then two biceps/triceps supersets', () {
    expect(ar(1), [
      'دفع دمبل جانبي كتف',
      'رفرفة دمبل أمامي كتف',
      'فراشة خلفي',
      'ترباس دمبل',
      'تبادل دمبل باي',
      'رفس كابل تراي',
      'شاكوش دمبل باي',
      'حبل خلفي تراي',
    ]);
    final supersets = [
      for (final e in plan.days[1].exercises)
        if (e.supersetWithNext) e.name.ar,
    ];
    expect(supersets, ['تبادل دمبل باي', 'شاكوش دمبل باي']);
  });

  test('day 3: legs and forearms', () {
    expect(ar(2), [
      'بار اسكوات حر',
      'دفع جهاز',
      'طعن دمبل',
      'جهاز أمامية',
      'جهاز خلفية',
      'سمانة جهاز',
      'ساعد مسطرة عكسي',
      'رست بار أمامي',
    ]);
  });

  test('day 4: chest and back, other exercises than day 1', () {
    expect(ar(3), [
      'بار عالي',
      'ظرافة',
      'دفع جهاز مستوي',
      'طرمبة واسع',
      'كابل تجميع من فوق',
      'جهاز همر ضيق',
      'بطن',
    ]);
  });

  test('day 5: shoulders, then three supersets', () {
    expect(ar(4), [
      'دفع جهاز أمامي كتف',
      'رفرفة دمبل جانبي كتف',
      'حبل على الوش',
      'ترباس بار سميث',
      'مسطرة كابل من تحت باي',
      'حبل خلفي تراي',
      'تكوير على جهاز الحصان',
      'دمبل زوجي تراي',
    ]);
    final supersets = [
      for (final e in plan.days[4].exercises)
        if (e.supersetWithNext) e.name.ar,
    ];
    expect(supersets, [
      'حبل على الوش',
      'مسطرة كابل من تحت باي',
      'تكوير على جهاز الحصان',
    ]);
  });

  test('exercise ids are unique within a day', () {
    for (final day in plan.days) {
      final ids = [for (final e in day.exercises) e.id];
      expect(ids.toSet(), hasLength(ids.length), reason: day.name.en);
    }
  });

  test('days 4 and 5 train the same muscles with other exercises', () {
    // Owner's plan (2026-11-10): only abs (day 1 and 4) and the rope
    // pushdown (day 2 and 5) repeat, so they share their history.
    Set<String> ids(int i) => {for (final e in plan.days[i].exercises) e.id};
    expect(plan.days[3].name, plan.days[0].name);
    expect(plan.days[4].name, plan.days[1].name);
    expect(ids(3).intersection(ids(0)), {'abs'});
    expect(ids(4).intersection(ids(1)), {'rope_pushdown'});
    expect(plan.days[3].exercises, hasLength(7));
    expect(plan.days[4].exercises, hasLength(8));
  });

  group('upgrade: old saved plans with days 4/5 copied from days 1/2', () {
    final old = WorkoutPlan(
      days: [
        for (final (i, d) in plan.days.indexed)
          WorkoutDay(
            id: d.id,
            name: d.name,
            exercises: switch (i) {
              3 => plan.days[0].exercises,
              4 => plan.days[1].exercises,
              _ => d.exercises,
            },
          ),
      ],
    );

    test('untouched copies get the real days 4 and 5', () {
      expect(PlanTemplates.upgrade(old).toJson(), plan.toJson());
    });

    test('a plan already right is returned as it is', () {
      expect(PlanTemplates.upgrade(plan), same(plan));
    });

    test('an edited day 4 or 5 is never changed', () {
      final edited = WorkoutPlan(
        days: [
          for (final (i, d) in old.days.indexed)
            if (i == 3)
              WorkoutDay(
                id: d.id,
                name: d.name,
                exercises: d.exercises.sublist(1),
              )
            else
              d,
        ],
      );
      expect(PlanTemplates.upgrade(edited), same(edited));
    });

    test('a plan without day-4 / day-5 ids is returned as it is', () {
      final mine = WorkoutPlan(days: [plan.days.first]);
      expect(PlanTemplates.upgrade(mine), same(mine));
    });
  });

  test('a superset never ends a day', () {
    for (final day in plan.days) {
      expect(day.exercises.last.supersetWithNext, isFalse);
    }
  });
}
