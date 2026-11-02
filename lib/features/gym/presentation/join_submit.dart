import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/features/gym/domain/entities/invite_code.dart';

/// What happens when the member confirms the code (delivery step 3/4: sign in
/// anonymously, call `redeem_invite`). Null until that exists: the screen then
/// shows the code and a hint, and the button stays off.
///
/// A link only ever pre-fills the field. This runs only after the member
/// taps "Join" (docs/decisions/gym_accounts.md §5).
typedef JoinSubmit = Future<void> Function(InviteCode code);

final joinSubmitProvider = Provider<JoinSubmit?>((ref) => null);
