import 'package:gym_tracker/features/workout/domain/entities/next_workout.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:meta/meta.dart';

/// The set to do now.
@immutable
class SetCursor {
  const new({
    required this.exerciseIndex,
    required this.setNumber,
    required this.weight,
    required this.reps,
    required this.restAfter,
    required this.supersetPartner,
  });

  /// Index in the day's exercises.
  final int exerciseIndex;

  /// 1-based.
  final int setNumber;

  /// Prefilled: today's last set of this exercise, else the suggestion,
  /// else 0 (first time: the member picks).
  final double weight;
  final int reps;

  /// Seconds of rest after logging this set; 0 inside a superset round
  /// (go straight to the partner).
  final int restAfter;

  /// The other exercise of the superset, if any (for "A" / "B" labels).
  final int? supersetPartner;
}

/// Order of sets in a day, with supersets: exercises linked by
/// [Exercise.supersetWithNext] are done round by round (A1, B1, rest,
/// A2, B2, rest…). Everything else is set by set with rest after each.
class WorkoutFlow {
  const new();

  /// Groups of exercise indexes: [0], [1], [4, 5] (superset), …
  List<List<int>> groups(WorkoutDay day) {
    final groups = <List<int>>[];
    var current = <int>[];
    for (var i = 0; i < day.exercises.length; i++) {
      current.add(i);
      if (!day.exercises[i].supersetWithNext || i == day.exercises.length - 1) {
        groups.add(current);
        current = [];
      }
    }
    return groups;
  }

  /// The planned order of (exercise index, set number).
  List<(int, int)> order(WorkoutDay day) => [
    for (final group in groups(day))
      for (
        var set = 1;
        set <=
            group
                .map((i) => day.exercises[i].targetSets)
                .reduce((a, b) => a > b ? a : b);
        set++
      )
        for (final i in group)
          if (set <= day.exercises[i].targetSets) (i, set),
  ];

  /// The next set to do, or null when every planned set is logged.
  SetCursor? next(
    WorkoutDay day,
    List<LoggedSet> logged,
    Map<String, WeightSuggestion> suggestions,
  ) {
    final count = <String, int>{};
    for (final s in logged) {
      count[s.exerciseId] = (count[s.exerciseId] ?? 0) + 1;
    }
    final allGroups = groups(day);
    for (final (index, setNumber) in order(day)) {
      final exercise = day.exercises[index];
      if ((count[exercise.id] ?? 0) >= setNumber) continue;

      final group = allGroups.firstWhere((g) => g.contains(index));
      final lastInRound = group.lastWhere(
        (i) => day.exercises[i].targetSets >= setNumber,
      );
      final today = [
        for (final s in logged)
          if (s.exerciseId == exercise.id) s,
      ];
      final suggestion = suggestions[exercise.id];
      return SetCursor(
        exerciseIndex: index,
        setNumber: setNumber,
        weight: today.isNotEmpty
            ? today.last.weight
            : (suggestion?.weight ?? 0),
        reps: today.isNotEmpty ? today.last.reps : exercise.targetReps,
        restAfter: index == lastInRound ? exercise.restSeconds : 0,
        supersetPartner: group.length > 1
            ? group.firstWhere((i) => i != index)
            : null,
      );
    }
    return null;
  }
}
