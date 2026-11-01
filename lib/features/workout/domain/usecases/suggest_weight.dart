import 'package:gym_tracker/features/workout/domain/entities/next_workout.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';

/// Suggests the next weight from last time's sets:
/// - every set hit the target reps → [Trend.up]: heaviest weight + one step
///   (50×12, 50×12, 50×12 → 52.5);
/// - average reps within 2 of the target → [Trend.keep]
///   (22.5×12, 22.5×12, 22.5×11 → 22.5);
/// - further off → [Trend.down]: one step lighter, never below 0;
/// - no history → [Trend.firstTime].
class SuggestWeight {
  const new();

  /// Average reps may miss the target by this much and still keep the weight.
  static const keepMargin = 2;

  WeightSuggestion call(Exercise exercise, List<LoggedSet> lastSets) {
    final sets = [
      for (final s in lastSets)
        if (s.reps > 0) s,
    ];
    if (sets.isEmpty) return const WeightSuggestion(trend: Trend.firstTime);

    final working = sets.map((s) => s.weight).reduce((a, b) => a > b ? a : b);
    final atWorking = sets.where((s) => s.weight == working).toList();
    final hitAll =
        sets.length >= exercise.targetSets &&
        atWorking.length >= exercise.targetSets &&
        atWorking.every((s) => s.reps >= exercise.targetReps);
    if (hitAll) {
      return WeightSuggestion(
        weight: working + exercise.weightStep,
        trend: Trend.up,
      );
    }

    final averageReps =
        atWorking.fold<int>(0, (sum, s) => sum + s.reps) / atWorking.length;
    if (averageReps >= exercise.targetReps - keepMargin) {
      return WeightSuggestion(weight: working, trend: Trend.keep);
    }
    final lighter = working - exercise.weightStep;
    return WeightSuggestion(
      weight: lighter < 0 ? 0 : lighter,
      trend: Trend.down,
    );
  }
}
