import 'package:gym_tracker/features/gym/domain/entities/gym_role.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:meta/meta.dart';

/// What the plan editor lets a person do, from their membership (the server
/// enforces the same rules in `save_plan`; the screens only mirror them).
@immutable
class PlanPermissions {
  const new({
    this.editTargets = true,
    this.editStructure = true,
    this.buildOwnPlan = true,
    this.canSave = true,
  });

  /// From a membership: owners and captains may change any plan; a trainee
  /// only what the captain switched on (`edit_plan` implies `edit_targets`).
  /// An inactive membership may change nothing.
  factory of(Membership? membership) {
    if (membership == null) return solo;
    if (!membership.isActive) return none;
    if (membership.role != GymRole.trainee) return solo;
    final p = membership.permissions;
    return PlanPermissions(
      editTargets: p.editTargets || p.editPlan,
      editStructure: p.editPlan,
      buildOwnPlan: p.buildOwnPlan,
    );
  }

  /// Training alone: everything.
  static const solo = PlanPermissions();

  /// Nothing: an ended membership, or no plan access.
  static const none = PlanPermissions(
    editTargets: false,
    editStructure: false,
    buildOwnPlan: false,
    canSave: false,
  );

  /// Sets, reps, rest and weight step.
  final bool editTargets;

  /// Add, rename, delete, reorder days and exercises, supersets.
  final bool editStructure;

  /// Make a plan when the captain has not made one yet.
  final bool buildOwnPlan;

  /// Any change at all.
  final bool canSave;

  bool get readOnly => !editTargets && !editStructure;

  @override
  bool operator ==(Object other) =>
      other is PlanPermissions &&
      other.editTargets == editTargets &&
      other.editStructure == editStructure &&
      other.buildOwnPlan == buildOwnPlan &&
      other.canSave == canSave;

  @override
  int get hashCode =>
      Object.hash(editTargets, editStructure, buildOwnPlan, canSave);
}

/// A gym plan as the server holds it (`plans`).
@immutable
class GymPlan {
  const new({
    required this.membershipId,
    required this.plan,
    required this.version,
    this.updatedBy,
  });

  final String membershipId;
  final WorkoutPlan plan;

  /// Grows on every change; the only truth for "did it change" (§11).
  final int version;

  /// The membership that made the last change (the trainee's own, or a
  /// manager's).
  final String? updatedBy;

  /// Someone else changed it last (the captain): the trainee gets the toast.
  bool get changedByOther => updatedBy != null && updatedBy != membershipId;
}

/// The phone's copy of a gym plan, for offline use.
@immutable
class StoredGymPlan {
  const new({
    required this.plan,
    required this.version,
    this.seenVersion = 0,
    this.pending,
  });

  final WorkoutPlan plan;
  final int version;

  /// The highest version the member was told about (toast once per version).
  final int seenVersion;

  /// A newer plan that arrived while a workout was in progress: it replaces
  /// [plan] when that workout ends. Until then the workout runs on [plan].
  final GymPlan? pending;

  StoredGymPlan copyWith({
    WorkoutPlan? plan,
    int? version,
    int? seenVersion,
    GymPlan? Function()? pending,
  }) => StoredGymPlan(
    plan: plan ?? this.plan,
    version: version ?? this.version,
    seenVersion: seenVersion ?? this.seenVersion,
    pending: pending == null ? this.pending : pending(),
  );
}

/// What a sync did.
@immutable
class PlanSyncOutcome {
  const new({
    this.replaced = false,
    this.deferred = false,
    this.toast = false,
    this.offline = false,
  });

  /// The local plan was replaced by the server's.
  final bool replaced;

  /// A newer plan is waiting for the workout in progress to end.
  final bool deferred;

  /// Tell the member "Your captain updated your plan".
  final bool toast;

  /// The server could not be reached; the local copy is what there is.
  final bool offline;
}
