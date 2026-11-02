import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_draft.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';

/// Where the plan and finished workouts live. Saved on the phone first, so
/// logging works offline.
abstract interface class WorkoutRepository {
  /// The member's plan, or null when they have none yet.
  Future<Result<WorkoutPlan?>> loadPlan();

  /// Saves the plan; a plan outside `PlanLimits` is refused with a
  /// `ValidationFailure`.
  Future<Result<void>> savePlan(WorkoutPlan plan);

  /// Finished workouts, oldest first.
  Future<Result<List<WorkoutSession>>> loadHistory();

  /// Saves a finished workout and clears the chosen day.
  Future<Result<void>> saveSession(WorkoutSession session);

  /// The day picked as next (by the member, or pinned by a plan edit), or
  /// null to follow the plan.
  Future<Result<ChosenDay?>> loadChosenDay();

  Future<Result<void>> saveChosenDay(ChosenDay? day);

  /// The workout in progress, or null.
  Future<Result<WorkoutDraft?>> loadDraft();

  /// Saves (or with null, discards) the workout in progress.
  Future<Result<void>> saveDraft(WorkoutDraft? draft);

  /// The highest level ever reached: climbing back to it is faster.
  Future<Result<Level>> loadBestLevel();

  Future<Result<void>> saveBestLevel(Level level);

  /// Erases finished workouts, the one in progress, the chosen day and the
  /// level on this phone (account deletion: "also erase workouts on this
  /// phone"). The plan stays.
  Future<Result<void>> clearHistory();
}
