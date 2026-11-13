import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';

/// Saves a round as its own session: one set of the exercise's library
/// entry, reps only (docs/designs/move_games.md §8). It counts in progress,
/// the level (in part) and backup like any workout; in a gym it uploads
/// with the membership like any workout.
///
/// A saved workout clears the "chosen day"; a round is not a plan day, so
/// the chosen day is put back.
class SaveMoveRound {
  const new(this._workouts);

  final WorkoutRepository _workouts;

  /// The same limit as a set logged in a workout
  /// (`ActiveWorkoutController.maxReps`).
  static const maxReps = 999;

  Future<Result<void>> call(RoundResult round) async {
    final reps = round.reps.clamp(0, maxReps);
    if (reps == 0) {
      return const Failed(ValidationFailure('a round with no reps'));
    }
    final chosen = await _workouts.loadChosenDay();
    final saved = await _workouts.saveSession(
      WorkoutSession(
        dayId: WorkoutSession.moveDayId,
        startedAt: round.startedAt,
        finishedAt: round.finishedAt,
        sets: [
          LoggedSet(
            exerciseId: round.exercise.catalogExerciseId,
            weight: 0,
            reps: reps,
          ),
        ],
      ),
    );
    if (saved is Failed<void>) return saved;
    if (chosen case Success(:final value?)) {
      // The workout is saved either way; a chosen day lost here only means
      // the plan's own next day shows.
      await _workouts.saveChosenDay(value);
    }
    return saved;
  }
}
