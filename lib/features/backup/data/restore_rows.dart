import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/usecases/plan_rules.dart';

/// What the account sends back, checked before it is trusted. The server
/// holds only what its own rules accepted, but the phone does not rely on
/// that: a row that is off in any way is skipped (and counted), never an
/// error, and never stored.
abstract final class RestoreRows {
  static final RegExp _id = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
  static final RegExp _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );
  static final DateTime _earliest = DateTime.utc(2020);

  /// A row of `workout_sessions` as a workout, or null when it is not one the
  /// app may store. [now] bounds the finish time (at most a day ahead).
  static WorkoutSession? session(Map<String, Object?> row, DateTime now) {
    try {
      final dayId = row['day_id'];
      if (dayId is! String || !_id.hasMatch(dayId)) return null;
      final finishedRaw = row['finished_at'];
      if (finishedRaw is! String) return null;
      final finished = DateTime.tryParse(finishedRaw)?.toUtc();
      if (finished == null ||
          finished.isBefore(_earliest) ||
          finished.isAfter(now.add(const Duration(days: 1)))) {
        return null;
      }
      final startedRaw = row['started_at'];
      DateTime? started;
      if (startedRaw != null) {
        if (startedRaw is! String) return null;
        started = DateTime.tryParse(startedRaw)?.toUtc();
        // Only the two bounds the server itself keeps: not after the end, at
        // most a day before it. Anything else is dropped, not the workout.
        if (started != null &&
            (started.isAfter(finished) ||
                finished.difference(started) > const Duration(days: 1))) {
          started = null;
        }
      }
      final membership = row['membership_id'];
      if (membership != null &&
          (membership is! String || !_uuid.hasMatch(membership))) {
        return null;
      }
      final rawSets = row['sets'];
      if (rawSets is! List<Object?> || rawSets.length > 500) return null;
      final sets = <LoggedSet>[];
      for (final raw in rawSets) {
        if (raw is! Map<String, Object?>) return null;
        final exercise = raw['exercise'];
        final weight = raw['weight'];
        final reps = raw['reps'];
        if (exercise is! String || !_id.hasMatch(exercise)) return null;
        if (weight is! num || weight < 0 || weight > 1000 || !weight.isFinite) {
          return null;
        }
        if (reps is! int || reps < 0 || reps > 1000) return null;
        sets.add(
          LoggedSet(
            exerciseId: exercise,
            weight: weight.toDouble(),
            reps: reps,
          ),
        );
      }
      return WorkoutSession(
        dayId: dayId,
        finishedAt: finished,
        startedAt: started,
        membershipId: membership as String?,
        sets: sets,
      );
    } on Object {
      return null;
    }
  }

  /// The body of `personal_plans` as a plan the editor accepts, or null.
  static WorkoutPlan? plan(Object? body) {
    try {
      if (body is! Map<String, Object?>) return null;
      final plan = WorkoutPlan.fromJson(body);
      return validatePlan(plan) == null ? plan : null;
    } on Object {
      return null;
    }
  }
}
