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
    required this.dayIndex,
    required this.finishedAt,
    required this.sets,
  });
  factory fromJson(Map<String, Object?> json) => WorkoutSession(
    dayIndex: json['day']! as int,
    finishedAt: DateTime.parse(json['finished_at']! as String),
    sets: [
      for (final s in json['sets']! as List<Object?>)
        LoggedSet.fromJson(s! as Map<String, Object?>),
    ],
  );

  final int dayIndex;
  final DateTime finishedAt;
  final List<LoggedSet> sets;

  List<LoggedSet> setsFor(String exerciseId) => [
    for (final s in sets)
      if (s.exerciseId == exerciseId) s,
  ];

  Map<String, Object?> toJson() => {
    'day': dayIndex,
    'finished_at': finishedAt.toUtc().toIso8601String(),
    'sets': [for (final s in sets) s.toJson()],
  };
}
