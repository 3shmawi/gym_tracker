import 'package:flutter/foundation.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout.dart';

enum WeightTrend {
  /// No history for this exercise yet.
  firstTime,

  /// Every planned set hit the target reps: go up one step.
  increase,

  /// Close to the target: stay at the same weight.
  keep,

  /// Far below the target: go down one step.
  decrease,
}

@immutable
class WeightSuggestion {
  const new({required this.trend, this.weightKg});

  final WeightTrend trend;

  /// Null when [trend] is [WeightTrend.firstTime].
  final double? weightKg;

  @override
  bool operator ==(Object other) =>
      other is WeightSuggestion &&
      other.trend == trend &&
      other.weightKg == weightKg;

  @override
  int get hashCode => Object.hash(trend, weightKg);

  @override
  String toString() => 'WeightSuggestion($trend, $weightKg)';
}

/// Double progression: keep the weight until every planned set reaches the
/// target reps, then add one step. If the average falls below 70% of the
/// target, drop one step.
///
/// The working weight is the heaviest weight used in the last session.
class SuggestNextWeight {
  const new();

  static const _decreaseBelow = 0.7;

  WeightSuggestion call({
    required PlanExercise exercise,
    required List<LoggedSet> lastSession,
  }) {
    if (lastSession.isEmpty) {
      return const WeightSuggestion(trend: WeightTrend.firstTime);
    }

    final working = lastSession
        .map((s) => s.weightKg)
        .reduce((a, b) => a > b ? a : b);
    final atWorking = lastSession.where((s) => s.weightKg == working).toList();

    final hitAllSets =
        lastSession.length >= exercise.sets &&
        atWorking.every((s) => s.reps >= exercise.targetReps);
    if (hitAllSets) {
      return WeightSuggestion(
        trend: WeightTrend.increase,
        weightKg: _round(working + exercise.weightStepKg),
      );
    }

    final averageReps =
        atWorking.map((s) => s.reps).reduce((a, b) => a + b) / atWorking.length;
    if (averageReps < exercise.targetReps * _decreaseBelow &&
        working - exercise.weightStepKg > 0) {
      return WeightSuggestion(
        trend: WeightTrend.decrease,
        weightKg: _round(working - exercise.weightStepKg),
      );
    }

    return WeightSuggestion(trend: WeightTrend.keep, weightKg: working);
  }

  static double _round(double kg) => (kg * 4).round() / 4;
}
