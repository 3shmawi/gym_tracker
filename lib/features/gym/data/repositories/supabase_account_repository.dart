import 'dart:async';

import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/account_session.dart';
import 'package:gym_tracker/features/gym/domain/repositories/account_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [AccountRepository] on Supabase Auth and the `delete-account` Edge
/// Function.
class SupabaseAccountRepository implements AccountRepository {
  new(this._client, {this.captchaToken});

  final SupabaseClient _client;

  /// The Turnstile token for the sign-in request, when it is configured.
  final Future<String?> Function()? captchaToken;

  static AccountSession _sessionOf(Session? session) {
    final user = session?.user;
    if (user == null) return AccountSession.signedOut;
    final email = user.email;
    return AccountSession(
      isSignedIn: true,
      isAnonymous: user.isAnonymous,
      email: email == null || email.isEmpty ? null : email,
    );
  }

  @override
  AccountSession get session => _sessionOf(_client.auth.currentSession);

  @override
  Stream<AccountSession> get sessionChanges => _client.auth.onAuthStateChange
      .map((state) => _sessionOf(state.session))
      .distinct();

  @override
  Future<Result<void>> signOut() => guard(_client.auth.signOut, retries: 0);

  @override
  Future<Result<void>> addEmail(String email) => guard(
    () => _client.auth.updateUser(UserAttributes(email: email.trim())),
    retries: 0,
  );

  @override
  Future<Result<void>> sendCode(String email) => guard(() async {
    final address = email.trim();
    if (_client.auth.currentSession?.user.isAnonymous ?? false) {
      // Same account, made permanent: the code confirms the new email.
      await _client.auth.updateUser(UserAttributes(email: address));
      return;
    }
    await _client.auth.signInWithOtp(
      email: address,
      shouldCreateUser: true,
      captchaToken: await captchaToken?.call(),
    );
  }, retries: 0);

  @override
  Future<Result<void>> verifyCode(String email, String code) => guard(() async {
    final anonymous = _client.auth.currentSession?.user.isAnonymous ?? false;
    await _client.auth.verifyOTP(
      type: anonymous ? OtpType.emailChange : OtpType.email,
      email: email.trim(),
      token: code.trim(),
    );
  }, retries: 0);

  @override
  Future<Result<void>> deleteAccount() => guard(() async {
    try {
      await _client.functions.invoke(
        'delete-account',
        body: {'confirm': 'delete'},
      );
    } on FunctionException catch (error) {
      final lastOwner = lastOwnerFailureFor(error);
      if (lastOwner != null) throw lastOwner;
      rethrow;
    }
    // The user is gone on the server: end the session here without asking
    // the server to revoke it (the call would only fail).
    await _client.auth.signOut();
  });

  /// `409 last_owner` carries the gym names; anything else stays generic.
  static LastOwnerFailure? lastOwnerFailureFor(FunctionException error) {
    if (error.status != 409) return null;
    final details = error.details;
    if (details is! Map || details['error'] != 'last_owner') return null;
    final gyms = details['gyms'];
    return LastOwnerFailure([
      if (gyms is List)
        for (final gym in gyms.take(20))
          if (gym is Map && gym['name'] is String) gym['name']! as String,
    ], error);
  }
}
