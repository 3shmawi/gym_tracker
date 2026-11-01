import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:meta/meta.dart';

/// What last time says about the next set's weight.
enum Trend {
  /// Hit every target rep last time: add one weight step.
  up,

  /// Close to the target: same weight again.
  keep,

  /// Fell well short: one step lighter.
  down,

  /// Never done: the member picks a weight.
  firstTime,
}

@immutable
class WeightSuggestion {
  const new({required this.trend, this.weight});

  /// kg; null when [trend] is [Trend.firstTime].
  final double? weight;
  final Trend trend;

  @override
  bool operator ==(Object other) =>
      other is WeightSuggestion &&
      other.weight == weight &&
      other.trend == trend;

  @override
  int get hashCode => Object.hash(weight, trend);

  @override
  String toString() => 'WeightSuggestion($weight, $trend)';
}

/// One row of the next workout: the exercise, last time, the suggestion.
@immutable
class ExercisePreview {
  const new({
    required this.exercise,
    required this.lastSets,
    required this.suggestion,
  });

  final Exercise exercise;
  final List<LoggedSet> lastSets;
  final WeightSuggestion suggestion;
}

/// The workout waiting for the member.
@immutable
class NextWorkout {
  const new({
    required this.dayIndex,
    required this.totalDays,
    required this.day,
    required this.exercises,
    this.waitingSince,
  });

  /// 0-based; shown as "Day dayIndex+1 of totalDays".
  final int dayIndex;
  final int totalDays;
  final WorkoutDay day;
  final List<ExercisePreview> exercises;

  /// Set when a day was skipped: the date this workout was first due. The
  /// plan doesn't move on by itself, so the screen says it waited.
  final DateTime? waitingSince;
}
