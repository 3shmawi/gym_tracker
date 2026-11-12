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

  /// Starts signing in by email code (backup, "I already have an account").
  /// An existing account signs in; a new email makes an account; the app never
  /// says which (the same answer either way). For an anonymous account (a
  /// gym trainee) it makes that account permanent instead: `auth.uid()`,
  /// memberships and history are unchanged, and the code confirms the email.
  Future<Result<void>> sendCode(String email);

  /// Confirms the 6-digit code sent to [email]. On success the session is
  /// permanent and `sessionChanges` says so. Wrong or expired codes are an
  /// `UnauthorizedFailure` (its cause says which; see `CodeProblem`).
  Future<Result<void>> verifyCode(String email, String code);

  /// Deletes the account on the server (`delete-account`). A sole owner of a
  /// gym with members gets a `LastOwnerFailure`.
  Future<Result<void>> deleteAccount();
}
