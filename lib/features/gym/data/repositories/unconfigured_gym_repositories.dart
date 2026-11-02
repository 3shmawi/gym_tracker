import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/account_session.dart';
import 'package:gym_tracker/features/gym/domain/entities/invite_code.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/repositories/account_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_repository.dart';

/// Used until `Dependencies.init` runs, in widget tests and when the env file
/// has no Supabase values: joining cannot work, and nothing crashes.
class UnconfiguredGymRepository implements GymRepository {
  const new();

  @override
  Future<Result<JoinedGym>> redeem(InviteCode code) async =>
      const Failed(NetworkFailure());

  @override
  Future<Result<List<Membership>>> loadMemberships() async =>
      const Success(<Membership>[]);
}

/// Signed out, always; every action fails with a network failure.
class UnconfiguredAccountRepository implements AccountRepository {
  const new();

  @override
  AccountSession get session => AccountSession.signedOut;

  @override
  Stream<AccountSession> get sessionChanges => const Stream.empty();

  @override
  Future<Result<void>> signOut() async => const Success(null);

  @override
  Future<Result<void>> addEmail(String email) async =>
      const Failed(NetworkFailure());

  @override
  Future<Result<void>> deleteAccount() async => const Failed(NetworkFailure());
}
