import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:meta/meta.dart';

/// A personal record: heavier than ever before on an exercise.
@immutable
class PersonalRecord {
  const new({
    required this.exerciseId,
    required this.weight,
    required this.reps,
  });

  final String exerciseId;
  final double weight;
  final int reps;
}

@immutable
class WorkoutSummary {
  const new({
    required this.sets,
    required this.volume,
    required this.records,
    required this.duration,
  });

  final int sets;

  /// Sum of weight × reps, kg.
  final double volume;
  final List<PersonalRecord> records;
  final Duration duration;
}

/// The short celebration at the end: sets, volume, records.
class SummarizeWorkout {
  const new();

  WorkoutSummary call(
    List<LoggedSet> today,
    List<WorkoutSession> history, {
    required DateTime startedAt,
    required DateTime now,
  }) {
    final best = <String, double>{};
    for (final session in history) {
      for (final s in session.sets) {
        if (s.reps <= 0) continue;
        final b = best[s.exerciseId];
        if (b == null || s.weight > b) best[s.exerciseId] = s.weight;
      }
    }
    final todayBest = <String, LoggedSet>{};
    for (final s in today) {
      if (s.reps <= 0) continue;
      final b = todayBest[s.exerciseId];
      if (b == null || s.weight > b.weight) todayBest[s.exerciseId] = s;
    }
    return WorkoutSummary(
      sets: today.length,
      volume: today.fold(0, (sum, s) => sum + s.weight * s.reps),
      duration: now.difference(startedAt),
      records: [
        for (final s in todayBest.values)
          // A record needs history to beat; first times aren't records.
          if (best[s.exerciseId] != null && s.weight > best[s.exerciseId]!)
            PersonalRecord(
              exerciseId: s.exerciseId,
              weight: s.weight,
              reps: s.reps,
            ),
      ],
    );
  }
}
