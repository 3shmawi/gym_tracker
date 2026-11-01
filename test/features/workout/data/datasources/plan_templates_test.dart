import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';

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

  test('exercise ids are unique within a day and shared across repeats', () {
    for (final day in plan.days) {
      final ids = [for (final e in day.exercises) e.id];
      expect(ids.toSet(), hasLength(ids.length), reason: day.name.en);
    }
    expect(
      [for (final e in plan.days[3].exercises) e.id],
      [for (final e in plan.days[0].exercises) e.id],
      reason: 'day 4 repeats day 1, so it shares its history',
    );
  });

  test('a superset never ends a day', () {
    for (final day in plan.days) {
      expect(day.exercises.last.supersetWithNext, isFalse);
    }
  });
}
