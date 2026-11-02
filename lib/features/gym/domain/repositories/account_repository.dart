import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/account_session.dart';

/// The person's sign-in on this phone.
abstract interface class AccountRepository {
  AccountSession get session;

  /// Emits whenever the session starts, changes (email added) or ends,
  /// including when the server refuses to refresh it (revoked, expired).
  Stream<AccountSession> get sessionChanges;

  /// Ends the session on this phone. For an anonymous account this is
  /// one-way: only a new code from the captain gets the person back in.
  Future<Result<void>> signOut();

  /// Starts making an anonymous account permanent: the server emails a link
  /// to [email]. `auth.uid()`, memberships and history are unchanged.
  Future<Result<void>> addEmail(String email);

  /// Deletes the account on the server (`delete-account`). A sole owner of a
  /// gym with members gets a `LastOwnerFailure`.
  Future<Result<void>> deleteAccount();
}
