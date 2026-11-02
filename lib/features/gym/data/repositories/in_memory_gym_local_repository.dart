import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/entities/workspace.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_local_repository.dart';

/// Keeps gym state in memory only: the default until `Dependencies.init`
/// runs, and a fake for tests.
class InMemoryGymLocalRepository implements GymLocalRepository {
  new({
    this.workspace = const SoloWorkspace(),
    List<Membership> memberships = const [],
    this.onboardingDone = false,
  }) : memberships = [...memberships];

  Workspace workspace;
  List<Membership> memberships;
  bool onboardingDone;

  @override
  Future<Result<Workspace>> loadWorkspace() async => Success(workspace);

  @override
  Future<Result<void>> saveWorkspace(Workspace workspace) async {
    this.workspace = workspace;
    return const Success(null);
  }

  @override
  Future<Result<List<Membership>>> loadMemberships() async =>
      Success([...memberships]);

  @override
  Future<Result<void>> saveMemberships(List<Membership> memberships) async {
    this.memberships = [...memberships];
    return const Success(null);
  }

  @override
  Future<Result<bool>> loadOnboardingDone() async => Success(onboardingDone);

  @override
  Future<Result<void>> saveOnboardingDone() async {
    onboardingDone = true;
    return const Success(null);
  }

  @override
  Future<Result<void>> clear() async {
    workspace = const SoloWorkspace();
    memberships = [];
    return const Success(null);
  }
}
