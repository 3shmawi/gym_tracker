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
    this.membershipId,
    this.startedAt,
  });
  factory fromJson(Map<String, Object?> json) => WorkoutSession(
    dayId: readDayId(json),
    finishedAt: DateTime.parse(json['finished_at']! as String),
    sets: [
      for (final s in json['sets']! as List<Object?>)
        LoggedSet.fromJson(s! as Map<String, Object?>),
    ],
    membershipId: json['membership_id'] as String?,
    startedAt: switch (json['started_at']) {
      final String s => DateTime.tryParse(s),
      _ => null,
    },
  );

  /// The plan day done ([WorkoutDay.id]).
  final String dayId;
  final DateTime finishedAt;
  final List<LoggedSet> sets;

  /// The gym membership it was logged in (`gym:<id>` workspace); null = solo.
  /// Not part of the workout's identity (the session id is a hash of the day,
  /// time and sets), only of where it is uploaded.
  final String? membershipId;

  /// When the workout started (from the workout in progress); null for
  /// workouts saved before this was kept. Only used for the gym dashboard's
  /// duration; not part of the workout's identity.
  final DateTime? startedAt;

  List<LoggedSet> setsFor(String exerciseId) => [
    for (final s in sets)
      if (s.exerciseId == exerciseId) s,
  ];

  Map<String, Object?> toJson() => {
    'day_id': dayId,
    'finished_at': finishedAt.toUtc().toIso8601String(),
    'sets': [for (final s in sets) s.toJson()],
    'membership_id': ?membershipId,
    'started_at': ?startedAt?.toUtc().toIso8601String(),
  };
}

/// The day id stored in a session or draft: `day_id`, or for data saved
/// before days had ids, the old 0-based position `day` mapped to
/// [legacyDayId].
String readDayId(Map<String, Object?> json) =>
    json['day_id'] as String? ?? legacyDayId(json['day']! as int);
