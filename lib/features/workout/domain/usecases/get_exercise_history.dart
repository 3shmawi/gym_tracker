import 'package:gym_tracker/features/workout/domain/entities/exercise_history.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';

/// The member's progress per exercise, from their finished workouts.
///
/// History is matched by exercise id, so an exercise that is on two plan
/// days (or was renamed) keeps one history. Sets with 0 reps (logged by
/// mistake) are left out.
class GetExerciseHistory {
  const new();

  /// One exercise's history, or null when [exerciseId] isn't in the plan.
  ExerciseHistory? call(
    WorkoutPlan plan,
    List<WorkoutSession> history,
    String exerciseId,
  ) {
    final exercise = _exercises(plan).where((e) => e.id == exerciseId);
    if (exercise.isEmpty) return null;
    final oldestFirst = _entries(history, exerciseId);
    return ExerciseHistory(
      progress: _progress(exercise.first, oldestFirst),
      entries: oldestFirst.reversed.toList(),
    );
  }

  /// Every exercise of the plan once, in plan order.
  List<ExerciseProgress> overview(
    WorkoutPlan plan,
    List<WorkoutSession> history,
  ) => [
    for (final e in _exercises(plan)) _progress(e, _entries(history, e.id)),
  ];

  static List<Exercise> _exercises(WorkoutPlan plan) {
    final seen = <String>{};
    return [
      for (final day in plan.days)
        for (final e in day.exercises)
          if (seen.add(e.id)) e,
    ];
  }

  /// Oldest first, with the change from the entry before.
  static List<HistoryEntry> _entries(
    List<WorkoutSession> history,
    String exerciseId,
  ) {
    final sessions = [...history]
      ..sort((a, b) => a.finishedAt.compareTo(b.finishedAt));
    final entries = <HistoryEntry>[];
    for (final s in sessions) {
      final sets = [
        for (final set in s.setsFor(exerciseId))
          if (set.reps > 0) set,
      ];
      if (sets.isEmpty) continue;
      final previous = entries.isEmpty ? null : entries.last;
      final entry = HistoryEntry(date: s.finishedAt, sets: sets);
      entries.add(
        HistoryEntry(
          date: entry.date,
          sets: sets,
          change: previous == null
              ? null
              : entry.topWeight - previous.topWeight,
        ),
      );
    }
    return entries;
  }

  static ExerciseProgress _progress(
    Exercise exercise,
    List<HistoryEntry> oldestFirst,
  ) {
    LoggedSet? best;
    for (final e in oldestFirst) {
      for (final s in e.sets) {
        if (best == null ||
            s.weight > best.weight ||
            (s.weight == best.weight && s.reps > best.reps)) {
          best = s;
        }
      }
    }
    return ExerciseProgress(
      exercise: exercise,
      first: oldestFirst.firstOrNull,
      latest: oldestFirst.lastOrNull,
      best: best,
      workouts: oldestFirst.length,
    );
  }
}
