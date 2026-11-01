import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_draft.dart';
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

  /// Saves a finished workout and clears the chosen day.
  Future<Result<void>> saveSession(WorkoutSession session);

  /// The day the member picked as next (0-based), or null to follow the plan.
  Future<Result<int?>> loadChosenDay();

  Future<Result<void>> saveChosenDay(int? dayIndex);

  /// The workout in progress, or null.
  Future<Result<WorkoutDraft?>> loadDraft();

  /// Saves (or with null, discards) the workout in progress.
  Future<Result<void>> saveDraft(WorkoutDraft? draft);
}
