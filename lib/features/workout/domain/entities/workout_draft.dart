import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:meta/meta.dart';

/// A workout in progress, saved after every change so a locked phone or a
/// killed app loses nothing.
@immutable
class WorkoutDraft {
  const new({
    required this.dayId,
    required this.startedAt,
    this.sets = const [],
    this.restEndsAt,
  });

  factory fromJson(Map<String, Object?> json) => WorkoutDraft(
    dayId: readDayId(json),
    startedAt: DateTime.parse(json['started_at']! as String),
    sets: [
      for (final s in json['sets']! as List<Object?>)
        LoggedSet.fromJson(s! as Map<String, Object?>),
    ],
    restEndsAt: json['rest_ends_at'] == null
        ? null
        : DateTime.parse(json['rest_ends_at']! as String),
  );

  /// The plan day being done (`WorkoutDay.id`). That day can't be edited
  /// until the workout is finished or discarded.
  final String dayId;
  final DateTime startedAt;

  /// Every set logged so far, in the order done.
  final List<LoggedSet> sets;

  /// When the current rest ends; null when not resting. A timestamp, not a
  /// countdown, so it survives the app being in the background or killed.
  final DateTime? restEndsAt;

  List<LoggedSet> setsFor(String exerciseId) => [
    for (final s in sets)
      if (s.exerciseId == exerciseId) s,
  ];

  WorkoutDraft copyWith({
    List<LoggedSet>? sets,
    DateTime? Function()? restEndsAt,
  }) => WorkoutDraft(
    dayId: dayId,
    startedAt: startedAt,
    sets: sets ?? this.sets,
    restEndsAt: restEndsAt == null ? this.restEndsAt : restEndsAt(),
  );

  Map<String, Object?> toJson() => {
    'day_id': dayId,
    'started_at': startedAt.toUtc().toIso8601String(),
    'sets': [for (final s in sets) s.toJson()],
    'rest_ends_at': restEndsAt?.toUtc().toIso8601String(),
  };
}
