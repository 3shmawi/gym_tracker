import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/entities/workspace.dart';

/// What the phone remembers about gyms: the active workspace, the last
/// memberships it saw (so the switcher works offline) and whether the first
/// screen ("how do you want to start?") was answered.
abstract interface class GymLocalRepository {
  Future<Result<Workspace>> loadWorkspace();
  Future<Result<void>> saveWorkspace(Workspace workspace);

  Future<Result<List<Membership>>> loadMemberships();
  Future<Result<void>> saveMemberships(List<Membership> memberships);

  Future<Result<bool>> loadOnboardingDone();
  Future<Result<void>> saveOnboardingDone();

  /// Forgets the workspace and the cached memberships (sign out, delete).
  Future<Result<void>> clear();
}
