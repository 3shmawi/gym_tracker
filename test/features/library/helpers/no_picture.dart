import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';

/// A library exercise that has no bundled picture, to test the placeholder
/// now that every real one has one.
const noPicture = LibraryExercise(
  defaults: Exercise(
    id: 'test_no_picture',
    name: LocalizedName(ar: 'تمرين بدون صورة', en: 'Exercise Without Picture'),
  ),
  muscle: MuscleGroup.core,
  equipment: [Equipment.bodyweight],
  steps: [
    LocalizedName(ar: 'الخطوة الأولى.', en: 'The first step.'),
    LocalizedName(ar: 'الخطوة التانية.', en: 'The second step.'),
  ],
);
