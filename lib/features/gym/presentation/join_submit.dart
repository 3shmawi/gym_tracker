import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/features/gym/domain/entities/invite_code.dart';
import 'package:gym_tracker/features/gym/presentation/join_controller.dart';

/// What happens when the member confirms the code: sign in anonymously if
/// needed and call `redeem_invite` (`JoinController`).
///
/// A link only ever pre-fills the field. This runs only after the member
/// taps "Join", or at once for a scanned QR (the person deliberately scanned;
/// docs/decisions/gym_accounts.md §5).
typedef JoinSubmit = Future<void> Function(InviteCode code, JoinVia via);

final joinSubmitProvider = Provider<JoinSubmit?>(
  (ref) =>
      (code, via) =>
          ref.read(joinControllerProvider.notifier).redeem(code, via: via),
);
