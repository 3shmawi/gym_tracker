import 'package:gym_tracker/features/gym/domain/entities/gym.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_role.dart';
import 'package:meta/meta.dart';

enum MembershipStatus {
  pending,
  active,
  ended;

  static MembershipStatus fromName(Object? name) => MembershipStatus.values
      .firstWhere((s) => s.name == name, orElse: () => MembershipStatus.ended);
}

/// A person's place in one gym.
@immutable
class Membership {
  const new({
    required this.id,
    required this.gym,
    required this.role,
    required this.status,
    this.permissions = const GymPermissions(),
    this.displayName,
    this.endedAt,
  });

  /// A row of `memberships` joined with its `gyms` row, as stored in the
  /// local cache and read from the server. Wrong shapes throw
  /// `FormatException`.
  factory fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final gym = json['gyms'] ?? json['gym'];
    if (id is! String || id.isEmpty || gym is! Map<String, Object?>) {
      throw const FormatException('membership without id or gym');
    }
    final endedAt = json['ended_at'];
    return Membership(
      id: id,
      gym: Gym.fromJson(gym),
      role: GymRole.fromName(json['role']),
      status: MembershipStatus.fromName(json['status']),
      permissions: json.containsKey('permissions')
          ? GymPermissions.fromJson(json['permissions'])
          : GymPermissions(
              editTargets: json['can_edit_targets'] == true,
              editPlan: json['can_edit_plan'] == true,
              buildOwnPlan: json['can_build_own_plan'] == true,
            ),
      displayName: json['display_name'] as String?,
      endedAt: endedAt is String ? DateTime.tryParse(endedAt) : null,
    );
  }

  final String id;
  final Gym gym;
  final GymRole role;
  final MembershipStatus status;
  final GymPermissions permissions;

  /// The name the captain typed when making the account.
  final String? displayName;
  final DateTime? endedAt;

  bool get isActive => status == MembershipStatus.active;

  /// Ended, and the gym lets the person read that history.
  bool get isReadOnly =>
      status == MembershipStatus.ended &&
      gym.historyAfterEnd == HistoryAfterEnd.readable;

  /// Ended, and the gym hid that history (never deleted).
  bool get isLocked =>
      status == MembershipStatus.ended &&
      gym.historyAfterEnd == HistoryAfterEnd.locked;

  Map<String, Object?> toJson() => {
    'id': id,
    'gym': {
      'id': gym.id,
      'name': gym.name,
      'history_after_end': gym.historyAfterEnd.name,
      'brand_color': gym.brandColor,
    },
    'role': role.name,
    'status': status.name,
    'permissions': {
      'edit_targets': permissions.editTargets,
      'edit_plan': permissions.editPlan,
      'build_own_plan': permissions.buildOwnPlan,
    },
    'display_name': displayName,
    'ended_at': endedAt?.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is Membership &&
      other.id == id &&
      other.gym == gym &&
      other.role == role &&
      other.status == status &&
      other.permissions == permissions &&
      other.displayName == displayName &&
      other.endedAt == endedAt;

  @override
  int get hashCode =>
      Object.hash(id, gym, role, status, permissions, displayName, endedAt);
}

/// What the server answers when a code is accepted.
@immutable
class JoinedGym {
  const new({
    required this.membershipId,
    required this.gym,
    required this.role,
    required this.permissions,
  });

  factory fromJson(Map<String, Object?> json) {
    final id = json['membership_id'];
    final gym = json['gym'];
    if (id is! String || id.isEmpty || gym is! Map<String, Object?>) {
      throw const FormatException('join answer without membership or gym');
    }
    return JoinedGym(
      membershipId: id,
      gym: Gym.fromJson(gym),
      role: GymRole.fromName(json['role']),
      permissions: GymPermissions.fromJson(json['permissions']),
    );
  }

  final String membershipId;
  final Gym gym;
  final GymRole role;
  final GymPermissions permissions;

  Membership toMembership() => Membership(
    id: membershipId,
    gym: gym,
    role: role,
    status: MembershipStatus.active,
    permissions: permissions,
  );
}
