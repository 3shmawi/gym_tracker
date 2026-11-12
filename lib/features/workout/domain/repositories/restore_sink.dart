import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';

/// Where restored workouts go: the phone's history, already marked as backed
/// up (nothing is uploaded again), and never twice (the key is the content).
abstract interface class RestoreSink {
  /// Adds the workouts that are not on the phone yet; returns how many.
  Future<int> addBackedUp(List<WorkoutSession> sessions);

  /// How many workouts the phone has (any, in any workspace).
  Future<int> count();
}
