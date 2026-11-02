import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/workspace.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_local_repository.dart';
import 'package:gym_tracker/features/gym/domain/usecases/refresh_memberships.dart';

/// Picks where the person trains. Solo is always allowed; a gym only while
/// the membership is active (an ended one can be read, never logged into).
class SwitchWorkspace {
  const new(this._local);

  final GymLocalRepository _local;

  Future<Result<GymSnapshot>> call(
    Workspace target,
    GymSnapshot current,
  ) async {
    if (target is GymWorkspace) {
      final member = current.memberships
          .where((m) => m.id == target.membershipId)
          .firstOrNull;
      if (member == null || !member.isActive) {
        return const Failed(ValidationFailure());
      }
    }
    final saved = await _local.saveWorkspace(target);
    return switch (saved) {
      Success() => Success(
        GymSnapshot(workspace: target, memberships: current.memberships),
      ),
      Failed(:final failure) => Failed(failure),
    };
  }
}
