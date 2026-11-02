import 'package:meta/meta.dart';

/// Who is signed in on this phone, as far as the UI needs to know. No ids and
/// no tokens: those stay in the data layer.
@immutable
class AccountSession {
  const new({this.isSignedIn = false, this.isAnonymous = false, this.email});

  static const signedOut = AccountSession();

  final bool isSignedIn;

  /// A trainee account with no email: signing out is one-way on this phone.
  final bool isAnonymous;
  final String? email;

  @override
  bool operator ==(Object other) =>
      other is AccountSession &&
      other.isSignedIn == isSignedIn &&
      other.isAnonymous == isAnonymous &&
      other.email == email;

  @override
  int get hashCode => Object.hash(isSignedIn, isAnonymous, email);
}
