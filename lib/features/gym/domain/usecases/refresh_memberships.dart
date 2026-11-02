import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/entities/workspace.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_local_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_repository.dart';

/// The workspace the person is in and the memberships they can pick from.
class GymSnapshot {
  const new({
    this.workspace = const SoloWorkspace(),
    this.memberships = const [],
  });

  final Workspace workspace;
  final List<Membership> memberships;

  Membership? get activeMembership => switch (workspace) {
    GymWorkspace(:final membershipId) =>
      memberships.where((m) => m.id == membershipId).firstOrNull,
    SoloWorkspace() => null,
  };
}

/// What the phone knows without asking the server (works offline).
class LoadGymSnapshot {
  const new(this._local);

  final GymLocalRepository _local;

  Future<GymSnapshot> call() async {
    final workspace = await _local.loadWorkspace();
    final memberships = await _local.loadMemberships();
    final snapshot = GymSnapshot(
      workspace: workspace.fold(
        onSuccess: (w) => w,
        onFailure: (_) => const SoloWorkspace(),
      ),
      memberships: memberships.fold(
        onSuccess: (m) => m,
        onFailure: (_) => const [],
      ),
    );
    return _soloUnlessActive(snapshot);
  }
}

/// Asks the server for the memberships, keeps a copy, and falls back to solo
/// when the active gym is gone or the membership ended (revoked, removed): a
/// person is never left inside a gym they can no longer train in.
class RefreshMemberships {
  const new(this._gyms, this._local);

  final GymRepository _gyms;
  final GymLocalRepository _local;

  Future<Result<GymSnapshot>> call() async {
    final remote = await _gyms.loadMemberships();
    switch (remote) {
      case Failed(:final failure):
        return Failed(failure);
      case Success(:final value):
        final workspace = await _local.loadWorkspace();
        final snapshot = _soloUnlessActive(
          GymSnapshot(
            workspace: workspace.fold(
              onSuccess: (w) => w,
              onFailure: (_) => const SoloWorkspace(),
            ),
            memberships: value,
          ),
        );
        await _local.saveMemberships(value);
        await _local.saveWorkspace(snapshot.workspace);
        return Success(snapshot);
    }
  }
}

GymSnapshot _soloUnlessActive(GymSnapshot snapshot) {
  final active = snapshot.activeMembership;
  if (snapshot.workspace is GymWorkspace && !(active?.isActive ?? false)) {
    return GymSnapshot(memberships: snapshot.memberships);
  }
  return snapshot;
}
