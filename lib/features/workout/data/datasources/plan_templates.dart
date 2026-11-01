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
        name: LocalizedName(ar: 'ضغط كتف دمبل', en: 'Dumbbell Shoulder Press'),
      ),
      Exercise(
        id: 'lateral_raise',
        name: LocalizedName(ar: 'رفرفة جانبي', en: 'Lateral Raise'),
        weightStep: 1,
      ),
      Exercise(
        id: 'alternating_db_curl',
        name: LocalizedName(ar: 'تبادل دمبل', en: 'Alternating Dumbbell Curl'),
        supersetWithNext: true,
      ),
      Exercise(
        id: 'cable_kickback',
        name: LocalizedName(ar: 'رفس كابل', en: 'Cable Kickback'),
      ),
      Exercise(
        id: 'hammer_curl',
        name: LocalizedName(ar: 'شاكوش دمبل', en: 'Hammer Curl'),
        supersetWithNext: true,
      ),
      Exercise(
        id: 'rope_pushdown',
        name: LocalizedName(ar: 'حبل خلفي', en: 'Rope Pushdown'),
      ),
    ],
  );

  static const _legs = WorkoutDay(
    name: LocalizedName(ar: 'رجل', en: 'Legs'),
    exercises: [
      Exercise(
        id: 'leg_press',
        name: LocalizedName(ar: 'دفع رجل جهاز', en: 'Leg Press'),
        weightStep: 5,
      ),
      Exercise(
        id: 'leg_extension',
        name: LocalizedName(ar: 'رجل أمامي', en: 'Leg Extension'),
      ),
      Exercise(
        id: 'leg_curl',
        name: LocalizedName(ar: 'رجل خلفي', en: 'Leg Curl'),
      ),
      Exercise(
        id: 'calf_raise',
        name: LocalizedName(ar: 'سمانة', en: 'Calf Raise'),
        targetReps: 15,
      ),
    ],
  );

  /// The 5-day split: بنش وضهر · كتف ودراع · رجل · بنش وضهر · كتف ودراع.
  static const fiveDaySplit = WorkoutPlan(
    days: [_chestBack, _shouldersArms, _legs, _chestBack, _shouldersArms],
  );
}
