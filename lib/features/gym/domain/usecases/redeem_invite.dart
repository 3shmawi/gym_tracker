import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/invite_code.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/entities/workspace.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_local_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_repository.dart';

/// Joins a gym with a code and makes it the active workspace.
///
/// The code is only ever sent after the member's tap, or at once for a
/// scanned QR (the person deliberately scanned). A failure leaves the
/// workspace untouched.
class RedeemInvite {
  const new(this._gyms, this._local);

  final GymRepository _gyms;
  final GymLocalRepository _local;

  Future<Result<JoinedGym>> call(InviteCode code) async {
    final result = await _gyms.redeem(code);
    if (result case Success(:final value)) {
      await _remember(value);
    }
    return result;
  }

  /// The server already has the membership; this only keeps the phone's copy
  /// in step. Failing to save it must not undo a successful join, so the
  /// results are not part of the answer (the next refresh heals them).
  Future<void> _remember(JoinedGym joined) async {
    final cached = await _local.loadMemberships();
    final others = switch (cached) {
      Success(:final value) => value.where((m) => m.id != joined.membershipId),
      Failed() => const <Membership>[],
    };
    await _local.saveMemberships([...others, joined.toMembership()]);
    await _local.saveWorkspace(GymWorkspace(joined.membershipId));
    await _local.saveOnboardingDone();
  }
}
