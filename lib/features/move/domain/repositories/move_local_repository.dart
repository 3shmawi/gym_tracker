import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';

/// Small things Move games keep on the phone: best scores, and whether the
/// form tip was seen, the camera was allowed once and the sound is on.
/// Nothing personal.
abstract interface class MoveLocalRepository {
  /// The most reps in one round of [kind], or null before the first one.
  Future<Result<int?>> best(MoveExerciseId exercise, RoundKind kind);

  /// Keeps [reps] when it beats the best; true when it did.
  Future<Result<bool>> offerBest(
    MoveExerciseId exercise,
    RoundKind kind,
    int reps,
  );

  Future<Result<bool>> tipSeen(MoveExerciseId exercise);
  Future<Result<void>> markTipSeen(MoveExerciseId exercise);

  /// The camera started once for Move games on this phone: the "why"
  /// screen is skipped (the camera plugin cannot ask the system without
  /// prompting).
  Future<Result<bool>> cameraAllowedBefore();
  Future<Result<void>> markCameraAllowed();

  /// The game's sounds are on (the default) or muted by the member.
  Future<Result<bool>> soundOn();
  Future<Result<void>> setSoundOn({required bool on});
}
