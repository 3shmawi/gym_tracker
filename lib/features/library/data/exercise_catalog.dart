// Content, not code: one sentence per step is easier to review unbroken.
// ignore_for_file: lines_longer_than_80_chars

import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';

/// The library's content. Seeded with every exercise of `PlanTemplates`, with
/// the same ids, names and starting targets (`exercise_catalog_test.dart`
/// keeps them in step), so history stays matched. To add one: a new, never
/// reused id (`snake_case`), both names, the muscle, the equipment, 2–3 steps.
abstract final class ExerciseCatalog {
  static const all = <LibraryExercise>[
    LibraryExercise(
      defaults: Exercise(
        id: 'flat_db_press',
        name: LocalizedName(ar: 'دفع دمبل مستوي', en: 'Flat Dumbbell Press'),
      ),
      muscle: MuscleGroup.chest,
      equipment: [Equipment.dumbbell, Equipment.bench],
      steps: [
        LocalizedName(
          ar: 'اتمدد على البنش ومسك دمبل في كل إيد عند الصدر، والكفوف لقدّام.',
          en: 'Lie on a flat bench with a dumbbell in each hand at chest level, palms forward.',
        ),
        LocalizedName(
          ar: 'ادفع لفوق لحد ما دراعاتك تتفرد من غير ما تقفل الكوع.',
          en: 'Press up until your arms are straight, without locking the elbows.',
        ),
        LocalizedName(
          ar: 'نزّل براحة في تانيتين لحد جنب صدرك.',
          en: 'Lower slowly for two seconds to the sides of your chest.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'wide_lat_pulldown',
        name: LocalizedName(ar: 'سحب عالي واسع', en: 'Wide Lat Pulldown'),
      ),
      muscle: MuscleGroup.back,
      equipment: [Equipment.machine],
      steps: [
        LocalizedName(
          ar: 'اقعد وثبّت فخدك تحت الوسادة، وامسك البار بمسكة أوسع من كتفك.',
          en: 'Sit with your thighs under the pad and hold the bar wider than your shoulders.',
        ),
        LocalizedName(
          ar: 'اسحب البار لحد أعلى صدرك وانت بتشد كتفك لورا ولتحت.',
          en: 'Pull the bar to your upper chest, drawing your shoulders back and down.',
        ),
        LocalizedName(
          ar: 'ارجع لفوق براحة من غير ما ترفع كتفك.',
          en: 'Return slowly without letting your shoulders rise.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'incline_machine_press',
        name: LocalizedName(ar: 'دفع جهاز عالي', en: 'Incline Machine Press'),
      ),
      muscle: MuscleGroup.chest,
      equipment: [Equipment.machine],
      steps: [
        LocalizedName(
          ar: 'اضبط الكرسي عشان المقابض تبقى عند أعلى صدرك، وضهرك ملزوق.',
          en: 'Set the seat so the handles are at upper-chest height, with your back flat on the pad.',
        ),
        LocalizedName(
          ar: 'ادفع المقابض لقدّام لحد ما دراعاتك تتفرد تقريباً.',
          en: 'Push the handles forward until your arms are almost straight.',
        ),
        LocalizedName(
          ar: 'ارجع براحة وحسّ بالشد في صدرك.',
          en: 'Return slowly and feel the stretch in your chest.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'close_grip_row',
        name: LocalizedName(ar: 'سحب أرضي ضيق', en: 'Close-Grip Seated Row'),
      ),
      muscle: MuscleGroup.back,
      equipment: [Equipment.cable],
      steps: [
        LocalizedName(
          ar: 'اقعد وركبك مثنية شوية، وامسك المقبض الضيق ودراعاتك متفردة.',
          en: 'Sit with slightly bent knees and hold the close handle with straight arms.',
        ),
        LocalizedName(
          ar: 'اسحب المقبض لبطنك وشد لوح كتفك ورا.',
          en: 'Pull the handle to your stomach and squeeze your shoulder blades together.',
        ),
        LocalizedName(
          ar: 'ارجع براحة من غير ما تنحني لقدّام.',
          en: 'Return slowly without leaning forward.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'pec_deck',
        name: LocalizedName(ar: 'فراشة', en: 'Pec Deck'),
      ),
      muscle: MuscleGroup.chest,
      equipment: [Equipment.machine],
      steps: [
        LocalizedName(
          ar: 'اقعد وضهرك ملزوق، ودراعاتك على الوسادات أو المقابض بمستوى صدرك.',
          en: 'Sit with your back on the pad and your arms on the pads or handles at chest height.',
        ),
        LocalizedName(
          ar: 'ضمّ دراعاتك قدّامك لحد ما يتقابلوا.',
          en: 'Bring your arms together in front of you until they meet.',
        ),
        LocalizedName(
          ar: 'افتح براحة لحد ما تحس بشد خفيف في صدرك.',
          en: 'Open slowly until you feel a light stretch in your chest.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'straight_arm_pulldown',
        name: LocalizedName(
          ar: 'مسطرة من فوق كابل',
          en: 'Straight-Arm Cable Pulldown',
        ),
      ),
      muscle: MuscleGroup.back,
      equipment: [Equipment.cable],
      steps: [
        LocalizedName(
          ar: 'قف قدّام الكابل العالي وامسك البار ودراعاتك شبه متفردة.',
          en: 'Stand facing the high cable and hold the bar with almost straight arms.',
        ),
        LocalizedName(
          ar: 'نزّل البار لحد فخدك بدراعات مفرودة من غير ما تثني الكوع.',
          en: 'Pull the bar down to your thighs with straight arms, without bending the elbows.',
        ),
        LocalizedName(
          ar: 'ارجع لفوق براحة وحسّ بالشد في ضهرك.',
          en: 'Return slowly and feel the stretch in your back.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'abs',
        name: LocalizedName(ar: 'بطن', en: 'Abs'),
        targetReps: 15,
        weightStep: 5,
      ),
      muscle: MuscleGroup.core,
      equipment: [Equipment.bodyweight],
      steps: [
        LocalizedName(
          ar: 'اتمدد على ضهرك وركبك مثنية، وإيدك جنب راسك من غير ما تشدها.',
          en: 'Lie on your back with bent knees and your hands by your head, without pulling it.',
        ),
        LocalizedName(
          ar: 'ارفع كتفك عن الأرض وانت بتشد عضلات بطنك.',
          en: 'Lift your shoulders off the floor, tightening your stomach muscles.',
        ),
        LocalizedName(ar: 'نزّل براحة وكرّر.', en: 'Lower slowly and repeat.'),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'db_shoulder_press',
        name: LocalizedName(
          ar: 'دفع دمبل جانبي كتف',
          en: 'Dumbbell Shoulder Press',
        ),
      ),
      muscle: MuscleGroup.shoulders,
      equipment: [Equipment.dumbbell, Equipment.bench],
      steps: [
        LocalizedName(
          ar: 'اقعد وضهرك ملزوق، والدمبل عند كتفك والكفوف لقدّام.',
          en: 'Sit with your back supported and the dumbbells at shoulder height, palms forward.',
        ),
        LocalizedName(
          ar: 'ادفع الدمبل لفوق لحد ما دراعاتك تتفرد فوق راسك.',
          en: 'Press the dumbbells up until your arms are straight overhead.',
        ),
        LocalizedName(
          ar: 'نزّل براحة لحد مستوى كتفك.',
          en: 'Lower slowly back to shoulder height.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'db_front_raise',
        name: LocalizedName(
          ar: 'رفرفة دمبل أمامي كتف',
          en: 'Dumbbell Front Raise',
        ),
        weightStep: 1,
      ),
      muscle: MuscleGroup.shoulders,
      equipment: [Equipment.dumbbell],
      steps: [
        LocalizedName(
          ar: 'قف ومسك دمبل قدّام فخدك، والكوع مثني شوية.',
          en: 'Stand holding a dumbbell in front of your thighs with slightly bent elbows.',
        ),
        LocalizedName(
          ar: 'ارفع الدمبل لقدّام لحد مستوى كتفك.',
          en: 'Raise the dumbbell forward to shoulder height.',
        ),
        LocalizedName(
          ar: 'نزّل براحة من غير ما تتهزّ بجسمك.',
          en: 'Lower slowly without swinging your body.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'reverse_pec_deck',
        name: LocalizedName(ar: 'فراشة خلفي', en: 'Reverse Pec Deck'),
      ),
      muscle: MuscleGroup.shoulders,
      equipment: [Equipment.machine],
      steps: [
        LocalizedName(
          ar: 'اقعد وصدرك على الوسادة ووشك للجهاز، وامسك المقابض.',
          en: 'Sit facing the machine with your chest on the pad and hold the handles.',
        ),
        LocalizedName(
          ar: 'افتح دراعاتك لورا لحد مستوى كتفك.',
          en: 'Open your arms backward to shoulder level.',
        ),
        LocalizedName(
          ar: 'ارجع براحة من غير ما تسيب الشد.',
          en: 'Return slowly without letting the weight rest.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'db_shrug',
        name: LocalizedName(ar: 'ترباس دمبل', en: 'Dumbbell Shrug'),
      ),
      muscle: MuscleGroup.shoulders,
      equipment: [Equipment.dumbbell],
      steps: [
        LocalizedName(
          ar: 'قف ومسك دمبل في كل إيد جنب جسمك.',
          en: 'Stand holding a dumbbell in each hand at your sides.',
        ),
        LocalizedName(
          ar: 'ارفع كتفك لأعلى ناحية ودنك من غير ما تلف الدراع.',
          en: 'Lift your shoulders straight up toward your ears without rolling them.',
        ),
        LocalizedName(
          ar: 'اثبت ثانية ونزّل براحة.',
          en: 'Hold for a second and lower slowly.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'alternating_db_curl',
        name: LocalizedName(
          ar: 'تبادل دمبل باي',
          en: 'Alternating Dumbbell Curl',
        ),
        supersetWithNext: true,
      ),
      muscle: MuscleGroup.arms,
      equipment: [Equipment.dumbbell],
      steps: [
        LocalizedName(
          ar: 'قف ومسك دمبل في كل إيد والكفوف لقدّام، والكوع ملزوق في جنبك.',
          en: 'Stand with a dumbbell in each hand, palms forward, elbows close to your sides.',
        ),
        LocalizedName(
          ar: 'اثني إيد لحد كتفك وانت بتلف الكف لفوق، وبعدين الإيد التانية.',
          en: 'Curl one arm up to your shoulder, turning the palm up, then the other.',
        ),
        LocalizedName(
          ar: 'نزّل براحة وما تتهزّش بضهرك.',
          en: 'Lower slowly without swinging your back.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'cable_kickback',
        name: LocalizedName(ar: 'رفس كابل تراي', en: 'Cable Kickback'),
      ),
      muscle: MuscleGroup.arms,
      equipment: [Equipment.cable],
      steps: [
        LocalizedName(
          ar: 'انحني لقدّام وامسك مقبض الكابل المنخفض، والكوع مثني وملزوق في جنبك.',
          en: 'Lean forward holding the low cable handle, with your elbow bent and tucked at your side.',
        ),
        LocalizedName(
          ar: 'مدّ دراعك لورا لحد ما تتفرد، والكوع ثابت.',
          en: 'Extend your arm back until it is straight, keeping the elbow still.',
        ),
        LocalizedName(
          ar: 'ارجع براحة لوضع البداية.',
          en: 'Return slowly to the start.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'hammer_curl',
        name: LocalizedName(ar: 'شاكوش دمبل باي', en: 'Hammer Curl'),
        supersetWithNext: true,
      ),
      muscle: MuscleGroup.arms,
      equipment: [Equipment.dumbbell],
      steps: [
        LocalizedName(
          ar: 'قف ومسك الدمبل بمسكة المطرقة: الكفوف ناحية بعض.',
          en: 'Stand holding the dumbbells in a hammer grip, palms facing each other.',
        ),
        LocalizedName(
          ar: 'اثني الدراع لحد كتفك من غير ما تلف الكف.',
          en: 'Curl up toward your shoulder without turning the wrist.',
        ),
        LocalizedName(
          ar: 'نزّل براحة والكوع ثابت جنبك.',
          en: 'Lower slowly with your elbow still at your side.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'rope_pushdown',
        name: LocalizedName(ar: 'حبل خلفي تراي', en: 'Rope Pushdown'),
      ),
      muscle: MuscleGroup.arms,
      equipment: [Equipment.cable],
      steps: [
        LocalizedName(
          ar: 'قف قدّام الكابل العالي وامسك الحبل والكوع ملزوق في جنبك.',
          en: 'Stand facing the high cable and hold the rope with your elbows tucked at your sides.',
        ),
        LocalizedName(
          ar: 'انزل بالحبل لتحت وفرّده للجنب في آخر الحركة.',
          en: 'Push the rope down and spread it apart at the bottom.',
        ),
        LocalizedName(
          ar: 'ارجع براحة لحد ما إيدك توصل صدرك.',
          en: 'Return slowly until your hands reach chest height.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'barbell_squat',
        name: LocalizedName(ar: 'بار اسكوات حر', en: 'Barbell Back Squat'),
        weightStep: 5,
        restSeconds: 120,
      ),
      muscle: MuscleGroup.legs,
      equipment: [Equipment.barbell, Equipment.rack],
      steps: [
        LocalizedName(
          ar: 'حط البار على أعلى ضهرك وقف بمسافة أوسع من كتفك شوية.',
          en: 'Rest the bar on your upper back and stand a little wider than your shoulders.',
        ),
        LocalizedName(
          ar: 'انزل بوركك لورا وتحت لحد ما فخدك يوازي الأرض، وضهرك مفرود.',
          en: 'Sit your hips back and down until your thighs are parallel to the floor, back straight.',
        ),
        LocalizedName(
          ar: 'اطلع بدفع الأرض بكعبك لحد ما تقف.',
          en: 'Drive up through your heels until you stand.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'leg_press',
        name: LocalizedName(ar: 'دفع جهاز', en: 'Leg Press'),
        weightStep: 5,
      ),
      muscle: MuscleGroup.legs,
      equipment: [Equipment.machine],
      steps: [
        LocalizedName(
          ar: 'اقعد وضهرك ملزوق وحط رجلك على المنصة بمسافة الكتف.',
          en: 'Sit with your back on the pad and your feet shoulder-width on the platform.',
        ),
        LocalizedName(
          ar: 'ادفع المنصة لحد ما رجلك تتفرد من غير ما تقفل الركبة.',
          en: 'Push the platform until your legs are straight, without locking the knees.',
        ),
        LocalizedName(
          ar: 'ارجع براحة لحد ما ركبتك تقرب من صدرك.',
          en: 'Return slowly until your knees come toward your chest.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'db_lunge',
        name: LocalizedName(ar: 'طعن دمبل', en: 'Dumbbell Lunge'),
      ),
      muscle: MuscleGroup.legs,
      equipment: [Equipment.dumbbell],
      steps: [
        LocalizedName(
          ar: 'قف ومسك دمبل في كل إيد، وخد خطوة كبيرة لقدّام.',
          en: 'Stand holding a dumbbell in each hand and take a long step forward.',
        ),
        LocalizedName(
          ar: 'انزل بركبتك الورانية لحد قرب الأرض، وركبة قدّام فوق كعبك.',
          en: 'Lower your back knee close to the floor, with the front knee above your heel.',
        ),
        LocalizedName(
          ar: 'ادفع بالرجل اللي قدّام ورجّع لوضع الوقوف.',
          en: 'Push through the front foot back to standing.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'leg_extension',
        name: LocalizedName(ar: 'جهاز أمامية', en: 'Leg Extension'),
      ),
      muscle: MuscleGroup.legs,
      equipment: [Equipment.machine],
      steps: [
        LocalizedName(
          ar: 'اقعد وحط كعب رجلك تحت الوسادة، والركبة على محور الجهاز.',
          en: 'Sit with your ankles under the pad and your knees in line with the machine axis.',
        ),
        LocalizedName(
          ar: 'افرد رجلك لحد ما تتفرد وشد عضلة الفخد.',
          en: 'Straighten your legs fully and squeeze your thigh.',
        ),
        LocalizedName(
          ar: 'نزّل براحة من غير ما تسيب الوزن يخبط.',
          en: 'Lower slowly without letting the weights drop.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'leg_curl',
        name: LocalizedName(ar: 'جهاز خلفية', en: 'Leg Curl'),
      ),
      muscle: MuscleGroup.legs,
      equipment: [Equipment.machine],
      steps: [
        LocalizedName(
          ar: 'اتمدد أو اقعد على الجهاز وحط الوسادة فوق كعب رجلك.',
          en: 'Lie or sit on the machine with the pad just above your heels.',
        ),
        LocalizedName(
          ar: 'اثني ركبتك وشد الوسادة ناحية مؤخرتك.',
          en: 'Bend your knees and pull the pad toward your glutes.',
        ),
        LocalizedName(
          ar: 'ارجع براحة لحد ما تتفرد.',
          en: 'Return slowly until your legs are straight.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'machine_calf_raise',
        name: LocalizedName(ar: 'سمانة جهاز', en: 'Machine Calf Raise'),
        weightStep: 5,
      ),
      muscle: MuscleGroup.legs,
      equipment: [Equipment.machine],
      steps: [
        LocalizedName(
          ar: 'حط مقدمة رجلك على الحافة والكعب برّه، والوسادة على كتفك.',
          en: 'Put the balls of your feet on the edge with your heels free and the pads on your shoulders.',
        ),
        LocalizedName(
          ar: 'اطلع على مقدمة رجلك لأعلى حد ممكن.',
          en: 'Rise onto your toes as high as you can.',
        ),
        LocalizedName(
          ar: 'نزّل الكعب تحت الحافة براحة لحد ما تحس بشد.',
          en: 'Lower your heels below the edge slowly until you feel a stretch.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'reverse_wrist_curl',
        name: LocalizedName(
          ar: 'ساعد مسطرة عكسي',
          en: 'Reverse Barbell Wrist Curl',
        ),
      ),
      muscle: MuscleGroup.arms,
      equipment: [Equipment.barbell, Equipment.bench],
      steps: [
        LocalizedName(
          ar: 'اقعد وسند ساعدك على فخدك أو البنش وامسك البار والكفوف لتحت.',
          en: 'Sit with your forearms resting on your thighs or a bench, holding the bar palms down.',
        ),
        LocalizedName(
          ar: 'ارفع البار بثني الرسغ لفوق.',
          en: 'Lift the bar by bending your wrists upward.',
        ),
        LocalizedName(
          ar: 'نزّل براحة وساعدك ثابت.',
          en: 'Lower slowly with your forearms still.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'barbell_wrist_curl',
        name: LocalizedName(ar: 'رست بار أمامي', en: 'Barbell Wrist Curl'),
      ),
      muscle: MuscleGroup.arms,
      equipment: [Equipment.barbell, Equipment.bench],
      steps: [
        LocalizedName(
          ar: 'اقعد وسند ساعدك على فخدك أو البنش وامسك البار والكفوف لفوق.',
          en: 'Sit with your forearms resting on your thighs or a bench, holding the bar palms up.',
        ),
        LocalizedName(
          ar: 'ارفع البار بثني الرسغ لفوق وشد عضلة الساعد.',
          en: 'Lift the bar by curling your wrists up and squeeze your forearms.',
        ),
        LocalizedName(
          ar: 'نزّل براحة لحد ما البار يقرب من أطراف صوابعك.',
          en: 'Lower slowly until the bar rolls toward your fingertips.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'incline_barbell_press',
        name: LocalizedName(ar: 'بار عالي', en: 'Incline Barbell Press'),
      ),
      muscle: MuscleGroup.chest,
      equipment: [Equipment.barbell, Equipment.bench],
      steps: [
        LocalizedName(
          ar: 'اتمدد على بنش مايل وامسك البار أوسع شوية من كتفك.',
          en: 'Lie on an incline bench and hold the bar a little wider than your shoulders.',
        ),
        LocalizedName(
          ar: 'نزّل البار براحة لحد أعلى صدرك.',
          en: 'Lower the bar slowly to your upper chest.',
        ),
        LocalizedName(
          ar: 'ادفع لفوق لحد ما دراعاتك تتفرد من غير ما تقفل الكوع.',
          en: 'Press up until your arms are straight, without locking the elbows.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'lat_pulldown_machine',
        name: LocalizedName(ar: 'ظرافة', en: 'Lat Pulldown Machine'),
      ),
      muscle: MuscleGroup.back,
      equipment: [Equipment.machine],
      steps: [
        LocalizedName(
          ar: 'اقعد على الجهاز وثبّت رجلك، وامسك المقابض.',
          en: 'Sit on the machine with your legs fixed and hold the handles.',
        ),
        LocalizedName(
          ar: 'اسحب لتحت لحد صدرك وانت بتضم لوحي كتفك.',
          en: 'Pull down to your chest while squeezing your shoulder blades.',
        ),
        LocalizedName(
          ar: 'ارجع لفوق براحة لحد ما ضهرك يتفرد.',
          en: 'Return slowly until your back is fully stretched.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'flat_machine_press',
        name: LocalizedName(
          ar: 'دفع جهاز مستوي',
          en: 'Flat Machine Chest Press',
        ),
      ),
      muscle: MuscleGroup.chest,
      equipment: [Equipment.machine],
      steps: [
        LocalizedName(
          ar: 'اضبط الكرسي عشان المقابض تبقى عند نص صدرك، وضهرك ملزوق.',
          en: 'Set the seat so the handles are at mid-chest, with your back flat on the pad.',
        ),
        LocalizedName(
          ar: 'ادفع المقابض لقدّام لحد ما دراعاتك تتفرد تقريباً.',
          en: 'Push the handles forward until your arms are almost straight.',
        ),
        LocalizedName(
          ar: 'ارجع براحة وحسّ بالشد في صدرك.',
          en: 'Return slowly and feel the stretch in your chest.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'wide_t_bar_row',
        name: LocalizedName(ar: 'طرمبة واسع', en: 'Wide-Grip T-Bar Row'),
      ),
      muscle: MuscleGroup.back,
      equipment: [Equipment.barbell, Equipment.machine],
      steps: [
        LocalizedName(
          ar: 'اقف على الجهاز، اطوي وسطك وضهرك مفرود، وامسك المقابض الواسعة.',
          en: 'Stand on the machine, hinge at the hips with a flat back and take the wide handles.',
        ),
        LocalizedName(
          ar: 'اسحب لحد صدرك وانت بتضم لوحي كتفك.',
          en: 'Pull to your chest while squeezing your shoulder blades.',
        ),
        LocalizedName(
          ar: 'نزّل براحة من غير ما ضهرك يتقوّس.',
          en: 'Lower slowly without rounding your back.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'high_cable_crossover',
        name: LocalizedName(
          ar: 'كابل تجميع من فوق',
          en: 'High Cable Crossover',
        ),
      ),
      muscle: MuscleGroup.chest,
      equipment: [Equipment.cable],
      steps: [
        LocalizedName(
          ar: 'ثبّت البكرتين فوق، وامسك مقبض في كل إيد وخطوة لقدّام.',
          en: 'Set both pulleys high, hold a handle in each hand and step forward.',
        ),
        LocalizedName(
          ar: 'هات إيديك لتحت وقدّام لحد ما يتقابلوا قدام وسطك.',
          en: 'Bring your hands down and forward until they meet in front of your hips.',
        ),
        LocalizedName(
          ar: 'ارجع براحة لحد ما تحس بالشد في صدرك.',
          en: 'Return slowly until you feel the stretch in your chest.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'hammer_close_grip_row',
        name: LocalizedName(ar: 'جهاز همر ضيق', en: 'Close-Grip Hammer Row'),
      ),
      muscle: MuscleGroup.back,
      equipment: [Equipment.machine],
      steps: [
        LocalizedName(
          ar: 'اقعد وصدرك على الوسادة، وامسك المقابض الضيقة.',
          en: 'Sit with your chest on the pad and hold the close handles.',
        ),
        LocalizedName(
          ar: 'اسحب لورا وكوعك جنب جسمك لحد ما تضم ضهرك.',
          en: 'Pull back with your elbows close to your body and squeeze your back.',
        ),
        LocalizedName(
          ar: 'ارجع براحة لحد ما دراعاتك تتفرد.',
          en: 'Return slowly until your arms are straight.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'machine_shoulder_press',
        name: LocalizedName(
          ar: 'دفع جهاز أمامي كتف',
          en: 'Machine Shoulder Press',
        ),
      ),
      muscle: MuscleGroup.shoulders,
      equipment: [Equipment.machine],
      steps: [
        LocalizedName(
          ar: 'اضبط الكرسي عشان المقابض تبقى عند كتفك، وضهرك ملزوق.',
          en: 'Set the seat so the handles are at shoulder height, with your back on the pad.',
        ),
        LocalizedName(
          ar: 'ادفع لفوق لحد ما دراعاتك تتفرد من غير ما تقفل الكوع.',
          en: 'Press up until your arms are straight, without locking the elbows.',
        ),
        LocalizedName(
          ar: 'نزّل براحة لحد مستوى كتفك.',
          en: 'Lower slowly back to shoulder height.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'db_lateral_raise',
        name: LocalizedName(
          ar: 'رفرفة دمبل جانبي كتف',
          en: 'Dumbbell Lateral Raise',
        ),
        weightStep: 1,
      ),
      muscle: MuscleGroup.shoulders,
      equipment: [Equipment.dumbbell],
      steps: [
        LocalizedName(
          ar: 'اقف ودمبل في كل إيد جنبك، وكوعك مثني شوية.',
          en: 'Stand with a dumbbell in each hand at your sides, elbows slightly bent.',
        ),
        LocalizedName(
          ar: 'ارفع الدمبل للجنب لحد مستوى كتفك.',
          en: 'Raise the dumbbells out to the sides up to shoulder height.',
        ),
        LocalizedName(
          ar: 'نزّل براحة من غير ما تتمرجح.',
          en: 'Lower slowly without swinging.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'face_pull',
        name: LocalizedName(ar: 'حبل على الوش', en: 'Face Pull'),
        supersetWithNext: true,
      ),
      muscle: MuscleGroup.shoulders,
      equipment: [Equipment.cable],
      steps: [
        LocalizedName(
          ar: 'ثبّت الحبل في الكابل عند مستوى وشك وامسكه بالإيدين.',
          en: 'Set the rope on a cable at face height and hold it with both hands.',
        ),
        LocalizedName(
          ar: 'اسحب الحبل لوشك وافتح إيديك للجناب وكوعك لفوق.',
          en: 'Pull the rope to your face, spreading your hands apart with elbows high.',
        ),
        LocalizedName(
          ar: 'ارجع براحة لحد ما دراعاتك تتفرد.',
          en: 'Return slowly until your arms are straight.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'smith_shrug',
        name: LocalizedName(ar: 'ترباس بار سميث', en: 'Smith Machine Shrug'),
      ),
      muscle: MuscleGroup.shoulders,
      equipment: [Equipment.machine, Equipment.barbell],
      steps: [
        LocalizedName(
          ar: 'اقف قدام بار السميث وامسكه بعرض كتفك ودراعاتك مفرودة.',
          en: 'Stand at the Smith bar and hold it shoulder-width with straight arms.',
        ),
        LocalizedName(
          ar: 'ارفع كتفك لفوق ناحية ودانك واثبت ثانية.',
          en: 'Lift your shoulders up toward your ears and hold for a second.',
        ),
        LocalizedName(
          ar: 'نزّل براحة من غير ما تلف كتفك.',
          en: 'Lower slowly without rolling your shoulders.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'cable_bar_curl',
        name: LocalizedName(
          ar: 'مسطرة كابل من تحت باي',
          en: 'Straight-Bar Cable Curl',
        ),
        supersetWithNext: true,
      ),
      muscle: MuscleGroup.arms,
      equipment: [Equipment.cable],
      steps: [
        LocalizedName(
          ar: 'ثبّت البار المستقيم في الكابل من تحت وامسكه والكفوف لفوق.',
          en: 'Attach a straight bar to a low cable and hold it palms up.',
        ),
        LocalizedName(
          ar: 'اثني كوعك وارفع البار لحد صدرك وكوعك ثابت جنبك.',
          en: 'Curl the bar to your chest, keeping your elbows at your sides.',
        ),
        LocalizedName(
          ar: 'نزّل براحة لحد ما دراعاتك تتفرد.',
          en: 'Lower slowly until your arms are straight.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'preacher_curl',
        name: LocalizedName(ar: 'تكوير على جهاز الحصان', en: 'Preacher Curl'),
        supersetWithNext: true,
      ),
      muscle: MuscleGroup.arms,
      equipment: [Equipment.machine, Equipment.bench],
      steps: [
        LocalizedName(
          ar: 'اقعد على جهاز الحصان وسند ضهر دراعك على الوسادة.',
          en: 'Sit at the preacher bench with the backs of your arms on the pad.',
        ),
        LocalizedName(
          ar: 'اثني كوعك وارفع الوزن لحد ما الباي يتقفل.',
          en: 'Curl the weight up until your biceps are fully squeezed.',
        ),
        LocalizedName(
          ar: 'نزّل براحة لحد ما دراعك يتفرد تقريباً.',
          en: 'Lower slowly until your arm is almost straight.',
        ),
      ],
    ),
    LibraryExercise(
      defaults: Exercise(
        id: 'db_overhead_extension',
        name: LocalizedName(
          ar: 'دمبل زوجي تراي',
          en: 'Two-Hand DB Overhead Extension',
        ),
      ),
      muscle: MuscleGroup.arms,
      equipment: [Equipment.dumbbell],
      steps: [
        LocalizedName(
          ar: 'امسك دمبل واحد بالإيدين فوق راسك ودراعاتك مفرودة.',
          en: 'Hold one dumbbell with both hands above your head, arms straight.',
        ),
        LocalizedName(
          ar: 'نزّل الدمبل ورا راسك بثني الكوع بس.',
          en: 'Lower the dumbbell behind your head by bending only your elbows.',
        ),
        LocalizedName(
          ar: 'افرد دراعاتك لفوق تاني وشد التراي.',
          en: 'Straighten your arms again and squeeze your triceps.',
        ),
      ],
    ),
  ];
}
