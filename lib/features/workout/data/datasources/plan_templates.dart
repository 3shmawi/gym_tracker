import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';

/// Ready-made plans a member can start from ("Start with a 5-day plan").
abstract final class PlanTemplates {
  static const _chestBack = WorkoutDay(
    name: LocalizedName(ar: 'بنش وضهر', en: 'Chest & Back'),
    exercises: [
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
    ],
  );

  static const _shouldersArms = WorkoutDay(
    name: LocalizedName(ar: 'كتف ودراع', en: 'Shoulders & Arms'),
    exercises: [
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
    ],
  );

  static const _legs = WorkoutDay(
    name: LocalizedName(ar: 'رجل', en: 'Legs'),
    exercises: [
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
    ],
  );

  /// The 5-day split: بنش وضهر · كتف ودراع · رجل · بنش وضهر · كتف ودراع.
  static const fiveDaySplit = WorkoutPlan(
    days: [_chestBack, _shouldersArms, _legs, _chestBack, _shouldersArms],
  );
}
