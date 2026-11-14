import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/library/data/exercise_catalog.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/usecases/plan_rules.dart';

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

  group('every ready plan (the picker)', () {
    final idPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
    final library = {for (final e in ExerciseCatalog.all) e.id: e.defaults};

    test('three plans, fewest days first, stable ids', () {
      expect(PlanTemplateId.values.map((t) => t.id), [
        'full_body_3',
        'upper_lower_4',
        'split_5',
      ]);
      expect(PlanTemplateId.values.map((t) => t.plan.days.length), [3, 4, 5]);
      expect(PlanTemplateId.split5.plan, same(PlanTemplates.fiveDaySplit));
    });

    test("within the server's plan rules (private.plan_problem)", () {
      for (final t in PlanTemplateId.values) {
        final plan = t.plan;
        expect(plan.days.length, inInclusiveRange(1, 14), reason: t.id);
        final json = jsonEncode(plan.toJson());
        expect(utf8.encode(json).length, lessThan(65536), reason: t.id);
        for (final d in plan.days) {
          expect(idPattern.hasMatch(d.id), isTrue, reason: d.id);
          expect(d.exercises.length, inInclusiveRange(1, 30), reason: d.id);
          final ids = [for (final e in d.exercises) e.id];
          expect(ids.toSet(), hasLength(ids.length), reason: d.id);
          for (final id in ids) {
            expect(idPattern.hasMatch(id), isTrue, reason: id);
          }
          expect(PlanNames.check(d.name.en), isNull, reason: d.id);
          expect(PlanNames.check(d.name.ar), isNull, reason: d.id);
        }
      }
    });

    test('no day id is shared between plans (each keeps its own history)', () {
      final ids = [
        for (final t in PlanTemplateId.values)
          for (final d in t.plan.days) d.id,
      ];
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('every exercise is from the library: same names and targets', () {
      for (final t in PlanTemplateId.values) {
        for (final d in t.plan.days) {
          for (final e in d.exercises) {
            final lib = library[e.id];
            expect(lib, isNotNull, reason: '${t.id}: ${e.id}');
            expect(e.name.en, lib!.name.en, reason: e.id);
            expect(e.name.ar, lib.name.ar, reason: e.id);
            expect(e.targetSets, lib.targetSets, reason: e.id);
            expect(e.targetReps, lib.targetReps, reason: e.id);
            expect(e.restSeconds, lib.restSeconds, reason: e.id);
            expect(e.weightStep, lib.weightStep, reason: e.id);
            expect(e.unit, lib.unit, reason: e.id);
          }
        }
      }
    });

    test('a superset is never the last exercise of a day', () {
      for (final t in PlanTemplateId.values) {
        for (final d in t.plan.days) {
          expect(d.exercises.last.supersetWithNext, isFalse, reason: d.id);
        }
      }
    });

    test('each plan trains legs, push and pull every week', () {
      bool has(PlanTemplateId t, Set<String> ids) =>
          t.plan.days.any((d) => d.exercises.any((e) => ids.contains(e.id)));
      for (final t in PlanTemplateId.values) {
        expect(has(t, {'barbell_squat', 'leg_press', 'db_lunge'}), isTrue);
        expect(
          has(t, {
            'flat_db_press',
            'incline_barbell_press',
            'flat_machine_press',
          }),
          isTrue,
        );
        expect(
          has(t, {
            'wide_lat_pulldown',
            'lat_pulldown_machine',
            'close_grip_row',
          }),
          isTrue,
        );
      }
    });

    test('a new plan is never mistaken for the old 5-day plan (upgrade)', () {
      for (final t in [PlanTemplateId.fullBody3, PlanTemplateId.upperLower4]) {
        expect(PlanTemplates.upgrade(t.plan), same(t.plan));
      }
    });

    test('round-trips through JSON (as saved on the phone)', () {
      for (final t in PlanTemplateId.values) {
        final back = WorkoutPlan.fromJson(
          jsonDecode(jsonEncode(t.plan.toJson())) as Map<String, Object?>,
        );
        expect(back.days.map((d) => d.id), t.plan.days.map((d) => d.id));
        expect(
          back.days.expand((d) => d.exercises).map((e) => e.id),
          t.plan.days.expand((d) => d.exercises).map((e) => e.id),
        );
      }
    });
  });
}
