import 'package:gym_tracker/features/gym/domain/entities/gym_role.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/l10n/l10n.dart';

String roleLabel(AppLocalizations l10n, GymRole role) => switch (role) {
  GymRole.owner => l10n.roleOwner,
  GymRole.captain => l10n.roleCaptain,
  GymRole.trainee => l10n.roleTrainee,
};

/// The memberships a person can train in now (not ended, not pending).
List<Membership> activeMemberships(List<Membership> all) => [
  for (final m in all)
    if (m.isActive) m,
];

/// Memberships that ended: readable or locked by their gym.
List<Membership> endedMemberships(List<Membership> all) => [
  for (final m in all)
    if (m.status == MembershipStatus.ended) m,
];
