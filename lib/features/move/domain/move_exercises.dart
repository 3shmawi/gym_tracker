import 'package:gym_tracker/features/move/domain/detectors/push_up_detector.dart';
import 'package:gym_tracker/features/move/domain/detectors/rep_detector.dart';
import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';

/// What is specific to each exercise. Adding one (pull-ups, squats…) is a
/// new [MoveExerciseId], a detector here, its placement guide and its
/// catalog entry (docs/designs/move_games.md §4.4).
abstract final class MoveExercises {
  /// A fresh detector for one round.
  static RepDetector detectorFor(MoveExerciseId id) => switch (id) {
    MoveExerciseId.pushUps => PushUpDetector(),
  };
}
