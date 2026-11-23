import 'package:gym_tracker/features/workout/domain/entities/next_workout.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/usecases/working_sets.dart';

/// Suggests the next weight from last time's sets:
/// - every set hit the target reps → [Trend.up]: heaviest weight + one step
///   (50×12, 50×12, 50×12 → 52.5);
/// - average reps within 2 of the target → [Trend.keep]
///   (22.5×12, 22.5×12, 22.5×11 → 22.5);
/// - further off → [Trend.down]: one step lighter, never below 0;
/// - no history → [Trend.firstTime].
///
/// A rep range ([Exercise.repsTop], "6–10", for sets to failure) uses double
/// progression instead (docs/designs/rep_ranges.md):
/// - at least the target number of working sets, every one at the top → ↑;
/// - the best working set at or above the bottom → → same weight;
/// - every working set below the bottom → ↓.
///
/// Units ([Exercise.unit]): a plate exercise moves one plate; a reps-only
/// one keeps weight 0 (the trend still says whether to push the reps).
class SuggestWeight {
  const new();

  /// Average reps may miss the target by this much and still keep the weight.
  static const keepMargin = 2;

  WeightSuggestion call(Exercise exercise, List<LoggedSet> lastSets) {
    final atWorking = workingSets(lastSets);
    if (atWorking.isEmpty) {
      return const WeightSuggestion(trend: Trend.firstTime);
    }
    // Plates move one plate at a time; reps only has no weight to change.
    final step = exercise.step;
    final working = atWorking.first.weight;
    if (exercise.repsTop case final top?) {
      return _range(exercise, atWorking, working, step, top);
    }

    // Working sets are a subset of the sets, so enough of them is enough.
    final hitAll =
        atWorking.length >= exercise.targetSets &&
        atWorking.every((s) => s.reps >= exercise.targetReps);
    if (hitAll) {
      return WeightSuggestion(weight: working + step, trend: Trend.up);
    }

    final averageReps =
        atWorking.fold<int>(0, (sum, s) => sum + s.reps) / atWorking.length;
    if (averageReps >= exercise.targetReps - keepMargin) {
      return WeightSuggestion(weight: working, trend: Trend.keep);
    }
    final lighter = working - step;
    return WeightSuggestion(
      weight: lighter < 0 ? 0 : lighter,
      trend: Trend.down,
    );
  }

  static WeightSuggestion _range(
    Exercise exercise,
    List<LoggedSet> atWorking,
    double working,
    double step,
    int top,
  ) {
    if (atWorking.length >= exercise.targetSets &&
        atWorking.every((s) => s.reps >= top)) {
      return WeightSuggestion(weight: working + step, trend: Trend.up);
    }
    if (atWorking.any((s) => s.reps >= exercise.targetReps)) {
      return WeightSuggestion(weight: working, trend: Trend.keep);
    }
    final lighter = working - step;
    return WeightSuggestion(
      weight: lighter < 0 ? 0 : lighter,
      trend: Trend.down,
    );
  }
}
