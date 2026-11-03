import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';

/// The gym's plan on the server.
abstract interface class GymPlanRepository {
  /// The plan of [membershipId], or null when the captain has made none.
  Future<Result<GymPlan?>> fetch(String membershipId);

  /// `save_plan(membership, base_version, body)`. The server refuses with
  /// `PlanChangedFailure` when [baseVersion] is not the current version,
  /// `UnauthorizedFailure` when the membership may not make this change, and
  /// `ValidationFailure` for a plan outside `PlanLimits`. [baseVersion] is 0
  /// for a first plan.
  Future<Result<GymPlan>> save(
    String membershipId,
    int baseVersion,
    WorkoutPlan plan,
  );
}

/// The phone's copy of each gym plan.
abstract interface class GymPlanStore {
  Future<Result<StoredGymPlan?>> load(String membershipId);
  Future<Result<void>> save(String membershipId, StoredGymPlan stored);
  Future<Result<void>> clear(String membershipId);
}
