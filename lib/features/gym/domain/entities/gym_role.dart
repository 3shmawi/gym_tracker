import 'package:meta/meta.dart';

enum GymRole {
  owner,
  captain,
  trainee;

  /// Unknown text is a trainee: the least a role can allow.
  static GymRole fromName(Object? name) => GymRole.values.firstWhere(
    (r) => r.name == name,
    orElse: () => GymRole.trainee,
  );
}

/// What a trainee may change in the plan their captain made
/// (docs/decisions/gym_accounts.md §1). The server enforces it; the app only
/// mirrors it.
@immutable
class GymPermissions {
  const new({
    this.editTargets = false,
    this.editPlan = false,
    this.buildOwnPlan = false,
  });

  factory fromJson(Object? json) {
    if (json is! Map<String, Object?>) return const GymPermissions();
    return GymPermissions(
      editTargets: json['edit_targets'] == true,
      editPlan: json['edit_plan'] == true,
      buildOwnPlan: json['build_own_plan'] == true,
    );
  }

  final bool editTargets;
  final bool editPlan;
  final bool buildOwnPlan;

  @override
  bool operator ==(Object other) =>
      other is GymPermissions &&
      other.editTargets == editTargets &&
      other.editPlan == editPlan &&
      other.buildOwnPlan == buildOwnPlan;

  @override
  int get hashCode => Object.hash(editTargets, editPlan, buildOwnPlan);
}
