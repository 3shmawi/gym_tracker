import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout.dart';

/// Offline-first workout data. Every write is saved on the device first and
/// returns immediately; [sync] pushes pending writes to the server when the
/// network is back (and pulls the latest plan).
abstract interface class WorkoutRepository {
  /// The active plan from the device cache, or null if none is cached yet.
  Future<AssignedPlan?> cachedPlan();

  /// Downloads the active plan (and recent history) and caches it.
  Future<Result<AssignedPlan?>> refreshPlan();

  /// The session that was started and not completed yet, if any.
  Future<WorkoutSession?> openSession();

  /// Sets of the last session for each exercise (by exercise, not machine).
  Future<Map<String, List<LoggedSet>>> lastSets(Iterable<String> exerciseIds);

  /// Sets already logged in [sessionId].
  Future<List<LoggedSet>> setsOf(String sessionId);

  Future<WorkoutSession> startSession(PlanDay day);

  Future<LoggedSet> logSet({
    required String sessionId,
    required String exerciseId,
    required int setNumber,
    required double weightKg,
    required int reps,
  });

  Future<void> updateSet(LoggedSet set);

  Future<void> deleteSet(String setId);

  /// Completes the session and moves the plan to the next day — locally at
  /// once, on the server on the next [sync].
  Future<AssignedPlan?> completeSession(String sessionId);

  /// Number of writes waiting to reach the server.
  Stream<int> watchPendingCount();

  /// Pushes pending writes in order. Stops at the first network failure
  /// and keeps the rest for the next call.
  Future<Result<int>> sync();
}
