import 'package:flutter/foundation.dart' show listEquals;
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';

/// Ready-made plans a member can start from ("Start with a 5-day plan").
abstract final class PlanTemplates {
  static const _chestBackName = LocalizedName(
    ar: 'بنش وضهر',
    en: 'Chest & Back',
  );
  static const _chestBack = <Exercise>[
    Exercise(
      id: 'flat_db_press',
      name: LocalizedName(ar: 'دفع دمبل مستوي', en: 'Flat Dumbbell Press'),
    ),
    Exercise(
      id: 'wide_lat_pulldown',
      name: LocalizedName(ar: 'سحب عالي واسع', en: 'Wide Lat Pulldown'),
    ),
    Exercise(
      id: 'incline_machine_press',
      name: LocalizedName(ar: 'دفع جهاز عالي', en: 'Incline Machine Press'),
    ),
    Exercise(
      id: 'close_grip_row',
      name: LocalizedName(ar: 'سحب أرضي ضيق', en: 'Close-Grip Seated Row'),
    ),
    Exercise(
      id: 'pec_deck',
      name: LocalizedName(ar: 'فراشة', en: 'Pec Deck'),
    ),
    Exercise(
      id: 'straight_arm_pulldown',
      name: LocalizedName(
        ar: 'مسطرة من فوق كابل',
        en: 'Straight-Arm Cable Pulldown',
      ),
    ),
    Exercise(
      id: 'abs',
      name: LocalizedName(ar: 'بطن', en: 'Abs'),
      targetReps: 15,
      weightStep: 5,
    ),
  ];

  static const _shouldersArmsName = LocalizedName(
    ar: 'كتف ودراع',
    en: 'Shoulders & Arms',
  );
  static const _shouldersArms = <Exercise>[
    Exercise(
      id: 'db_shoulder_press',
      name: LocalizedName(
        ar: 'دفع دمبل جانبي كتف',
        en: 'Dumbbell Shoulder Press',
      ),
    ),
    Exercise(
      id: 'db_front_raise',
      name: LocalizedName(
        ar: 'رفرفة دمبل أمامي كتف',
        en: 'Dumbbell Front Raise',
      ),
      weightStep: 1,
    ),
    Exercise(
      id: 'reverse_pec_deck',
      name: LocalizedName(ar: 'فراشة خلفي', en: 'Reverse Pec Deck'),
    ),
    Exercise(
      id: 'db_shrug',
      name: LocalizedName(ar: 'ترباس دمبل', en: 'Dumbbell Shrug'),
    ),
    // Biceps & triceps: two supersets.
    Exercise(
      id: 'alternating_db_curl',
      name: LocalizedName(
        ar: 'تبادل دمبل باي',
        en: 'Alternating Dumbbell Curl',
      ),
      supersetWithNext: true,
    ),
    Exercise(
      id: 'cable_kickback',
      name: LocalizedName(ar: 'رفس كابل تراي', en: 'Cable Kickback'),
    ),
    Exercise(
      id: 'hammer_curl',
      name: LocalizedName(ar: 'شاكوش دمبل باي', en: 'Hammer Curl'),
      supersetWithNext: true,
    ),
    Exercise(
      id: 'rope_pushdown',
      name: LocalizedName(ar: 'حبل خلفي تراي', en: 'Rope Pushdown'),
    ),
  ];

  static const _legsName = LocalizedName(ar: 'رجل', en: 'Legs');
  static const _legs = <Exercise>[
    Exercise(
      id: 'barbell_squat',
      name: LocalizedName(ar: 'بار اسكوات حر', en: 'Barbell Back Squat'),
      weightStep: 5,
      restSeconds: 120,
    ),
    Exercise(
      id: 'leg_press',
      name: LocalizedName(ar: 'دفع جهاز', en: 'Leg Press'),
      weightStep: 5,
    ),
    Exercise(
      id: 'db_lunge',
      name: LocalizedName(ar: 'طعن دمبل', en: 'Dumbbell Lunge'),
    ),
    Exercise(
      id: 'leg_extension',
      name: LocalizedName(ar: 'جهاز أمامية', en: 'Leg Extension'),
    ),
    Exercise(
      id: 'leg_curl',
      name: LocalizedName(ar: 'جهاز خلفية', en: 'Leg Curl'),
    ),
    Exercise(
      id: 'machine_calf_raise',
      name: LocalizedName(ar: 'سمانة جهاز', en: 'Machine Calf Raise'),
      weightStep: 5,
    ),
    Exercise(
      id: 'reverse_wrist_curl',
      name: LocalizedName(
        ar: 'ساعد مسطرة عكسي',
        en: 'Reverse Barbell Wrist Curl',
      ),
    ),
    Exercise(
      id: 'barbell_wrist_curl',
      name: LocalizedName(ar: 'رست بار أمامي', en: 'Barbell Wrist Curl'),
    ),
  ];

  // Day 4: a second chest & back day with other exercises (owner's plan,
  // 2026-11-10). Abs is the same exercise as day 1, so it keeps its history.
  static const _chestBack2 = <Exercise>[
    Exercise(
      id: 'incline_barbell_press',
      name: LocalizedName(ar: 'بار عالي', en: 'Incline Barbell Press'),
    ),
    Exercise(
      id: 'lat_pulldown_machine',
      name: LocalizedName(ar: 'ظرافة', en: 'Lat Pulldown Machine'),
    ),
    Exercise(
      id: 'flat_machine_press',
      name: LocalizedName(ar: 'دفع جهاز مستوي', en: 'Flat Machine Chest Press'),
    ),
    Exercise(
      id: 'wide_t_bar_row',
      name: LocalizedName(ar: 'طرمبة واسع', en: 'Wide-Grip T-Bar Row'),
    ),
    Exercise(
      id: 'high_cable_crossover',
      name: LocalizedName(ar: 'كابل تجميع من فوق', en: 'High Cable Crossover'),
    ),
    Exercise(
      id: 'hammer_close_grip_row',
      name: LocalizedName(ar: 'جهاز همر ضيق', en: 'Close-Grip Hammer Row'),
    ),
    Exercise(
      id: 'abs',
      name: LocalizedName(ar: 'بطن', en: 'Abs'),
      targetReps: 15,
      weightStep: 5,
    ),
  ];

  // Day 5: a second shoulders & arms day. Rope pushdown is day 2's exercise.
  static const _shouldersArms2 = <Exercise>[
    Exercise(
      id: 'machine_shoulder_press',
      name: LocalizedName(
        ar: 'دفع جهاز أمامي كتف',
        en: 'Machine Shoulder Press',
      ),
    ),
    Exercise(
      id: 'db_lateral_raise',
      name: LocalizedName(
        ar: 'رفرفة دمبل جانبي كتف',
        en: 'Dumbbell Lateral Raise',
      ),
      weightStep: 1,
    ),
    Exercise(
      id: 'face_pull',
      name: LocalizedName(ar: 'حبل على الوش', en: 'Face Pull'),
      supersetWithNext: true,
    ),
    Exercise(
      id: 'smith_shrug',
      name: LocalizedName(ar: 'ترباس بار سميث', en: 'Smith Machine Shrug'),
    ),
    // Biceps & triceps: two supersets.
    Exercise(
      id: 'cable_bar_curl',
      name: LocalizedName(
        ar: 'مسطرة كابل من تحت باي',
        en: 'Straight-Bar Cable Curl',
      ),
      supersetWithNext: true,
    ),
    Exercise(
      id: 'rope_pushdown',
      name: LocalizedName(ar: 'حبل خلفي تراي', en: 'Rope Pushdown'),
    ),
    Exercise(
      id: 'preacher_curl',
      name: LocalizedName(ar: 'تكوير على جهاز الحصان', en: 'Preacher Curl'),
      supersetWithNext: true,
    ),
    Exercise(
      id: 'db_overhead_extension',
      name: LocalizedName(
        ar: 'دمبل زوجي تراي',
        en: 'Two-Hand DB Overhead Extension',
      ),
    ),
  ];

  /// The 5-day split: بنش وضهر · كتف ودراع · رجل · بنش وضهر · كتف ودراع.
  /// Days 4 and 5 train the same muscles as days 1 and 2 with other
  /// exercises. Day ids are `day-1` … `day-5`, the ids plans saved before days
  /// had ids get (`legacyDayId`), so old history keeps pointing at the same
  /// days.
  static const fiveDaySplit = WorkoutPlan(
    days: [
      WorkoutDay(id: 'day-1', name: _chestBackName, exercises: _chestBack),
      WorkoutDay(
        id: 'day-2',
        name: _shouldersArmsName,
        exercises: _shouldersArms,
      ),
      WorkoutDay(id: 'day-3', name: _legsName, exercises: _legs),
      WorkoutDay(id: 'day-4', name: _chestBackName, exercises: _chestBack2),
      WorkoutDay(
        id: 'day-5',
        name: _shouldersArmsName,
        exercises: _shouldersArms2,
      ),
    ],
  );

  /// Until 2026-11-10 the template's days 4 and 5 were copies of days 1 and
  /// 2 (the same exercises twice a week). A saved plan whose day 4 and day 5
  /// are still exactly those copies (never edited) gets the real days 4 and
  /// 5; anything else is returned as it is. Names, ids and the other days
  /// never change, so history and the waiting workout stay put.
  static WorkoutPlan upgrade(WorkoutPlan plan) {
    bool untouched(WorkoutDay day, String id, List<Exercise> copy) =>
        day.id == id && listEquals(day.exercises, copy);
    final days = plan.days;
    final i4 = days.indexWhere((d) => d.id == 'day-4');
    final i5 = days.indexWhere((d) => d.id == 'day-5');
    if (i4 < 0 || i5 < 0) return plan;
    if (!untouched(days[i4], 'day-4', _chestBack) ||
        !untouched(days[i5], 'day-5', _shouldersArms)) {
      return plan;
    }
    return WorkoutPlan(
      days: [
        for (final (i, d) in days.indexed)
          if (i == i4)
            WorkoutDay(id: d.id, name: d.name, exercises: _chestBack2)
          else if (i == i5)
            WorkoutDay(id: d.id, name: d.name, exercises: _shouldersArms2)
          else
            d,
      ],
    );
  }
}
