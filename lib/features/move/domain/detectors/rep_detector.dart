import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_state.dart';

/// Turns a stream of pose frames into reps and live state for one exercise.
/// One instance per round; it keeps state between frames.
abstract interface class RepDetector {
  MoveExerciseId get exercise;

  /// Feeds one frame; returns the live state and what it noticed. Never
  /// throws, whatever the frame holds.
  RepUpdate onFrame(PoseFrame frame);

  /// Back to the start of a round.
  void reset();
}
