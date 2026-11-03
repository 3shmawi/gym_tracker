import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:meta/meta.dart';

/// The big muscle groups the library is filtered by.
enum MuscleGroup {
  chest,
  back,
  shoulders,
  arms,
  legs,
  core;

  static MuscleGroup? fromName(String? name) =>
      values.where((m) => m.name == name).firstOrNull;
}

/// What an exercise needs. An exercise may need several (dumbbells and a
/// bench); [bodyweight] means nothing at all.
enum Equipment {
  dumbbell,
  barbell,
  bench,
  rack,
  machine,
  cable,
  bodyweight;

  static Equipment? fromName(String? name) =>
      values.where((e) => e.name == name).firstOrNull;
}

/// One exercise of the shared library: a stable id, names in both languages,
/// the muscle and the equipment, 2–3 short steps, and the targets a plan
/// starts it with.
///
/// The id is the same id the plan and the history use, so adding an exercise
/// from the library puts a member's earlier workouts of it back on its
/// progress. Never change an id; never reuse one for another exercise.
@immutable
class LibraryExercise {
  const new({
    required this.defaults,
    required this.muscle,
    required this.equipment,
    required this.steps,
  });

  /// The exercise as a plan starts it: id, name and targets.
  final Exercise defaults;
  final MuscleGroup muscle;
  final List<Equipment> equipment;

  /// 2–3 short steps, in order.
  final List<LocalizedName> steps;

  String get id => defaults.id;
  LocalizedName get name => defaults.name;

  /// The key of the picture: its files are `assets/exercises/<key>.webp` and
  /// `<key>_thumb.webp` (see `ExerciseImages`), derived from the id, never
  /// typed.
  /// Without a picture the screens draw a placeholder.
  String get illustrationKey => id;

  /// Steps allowed per exercise.
  static const minSteps = 2;
  static const maxSteps = 3;

  /// Characters per step, in each language.
  static const maxStepLength = 140;
}
