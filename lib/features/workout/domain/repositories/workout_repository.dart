import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';

/// Where the plan and finished workouts live. Saved on the phone first, so
/// logging works offline.
abstract interface class WorkoutRepository {
  /// The member's plan, or null when they have none yet.
  Future<Result<WorkoutPlan?>> loadPlan();

  Future<Result<void>> savePlan(WorkoutPlan plan);

  /// Finished workouts, oldest first.
  Future<Result<List<WorkoutSession>>> loadHistory();

  Future<Result<void>> saveSession(WorkoutSession session);
}
