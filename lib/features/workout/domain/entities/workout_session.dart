import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:meta/meta.dart';

/// One logged set.
@immutable
class LoggedSet {
  const new({
    required this.exerciseId,
    required this.weight,
    required this.reps,
  });
  factory fromJson(Map<String, Object?> json) => LoggedSet(
    exerciseId: json['exercise']! as String,
    weight: (json['weight']! as num).toDouble(),
    reps: json['reps']! as int,
  );

  final String exerciseId;

  /// kg.
  final double weight;
  final int reps;

  Map<String, Object?> toJson() => {
    'exercise': exerciseId,
    'weight': weight,
    'reps': reps,
  };

  @override
  bool operator ==(Object other) =>
      other is LoggedSet &&
      other.exerciseId == exerciseId &&
      other.weight == weight &&
      other.reps == reps;

  @override
  int get hashCode => Object.hash(exerciseId, weight, reps);
}

/// A finished workout: which plan day, when, and every set.
@immutable
class WorkoutSession {
  const new({
    required this.dayId,
    required this.finishedAt,
    required this.sets,
  });
  factory fromJson(Map<String, Object?> json) => WorkoutSession(
    dayId: readDayId(json),
    finishedAt: DateTime.parse(json['finished_at']! as String),
    sets: [
      for (final s in json['sets']! as List<Object?>)
        LoggedSet.fromJson(s! as Map<String, Object?>),
    ],
  );

  /// The plan day done ([WorkoutDay.id]).
  final String dayId;
  final DateTime finishedAt;
  final List<LoggedSet> sets;

  List<LoggedSet> setsFor(String exerciseId) => [
    for (final s in sets)
      if (s.exerciseId == exerciseId) s,
  ];

  Map<String, Object?> toJson() => {
    'day_id': dayId,
    'finished_at': finishedAt.toUtc().toIso8601String(),
    'sets': [for (final s in sets) s.toJson()],
  };
}

/// The day id stored in a session or draft: `day_id`, or for data saved
/// before days had ids, the old 0-based position `day` mapped to
/// [legacyDayId].
String readDayId(Map<String, Object?> json) =>
    json['day_id'] as String? ?? legacyDayId(json['day']! as int);
