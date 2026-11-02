import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/invite_code.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';

/// The server side of gyms: joining with a code and reading memberships.
/// Never throws; an `InviteFailure` says why a code was refused.
abstract interface class GymRepository {
  /// Signs in anonymously when there is no session yet, then redeems [code].
  /// The same phone retrying a code it already used gets the same success.
  Future<Result<JoinedGym>> redeem(InviteCode code);

  /// The person's memberships, active and ended. Empty without a session.
  Future<Result<List<Membership>>> loadMemberships();
}
