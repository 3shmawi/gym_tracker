import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Every error the UI can show, independent of where it came from
/// (Supabase, HTTP, platform). Repositories return these inside a `Result`
/// instead of throwing.
@immutable
sealed class AppFailure implements Exception {
  const new([this.cause]);

  /// The original error, for logs and monitoring — never shown to users.
  final Object? cause;

  /// Worth retrying automatically (the device or server may recover).
  bool get isRetryable => false;

  /// Maps any thrown error to a failure.
  static AppFailure from(Object error) => switch (error) {
    AppFailure() => error,
    SocketException() || HttpException() => NetworkFailure(error),
    TimeoutException() => TimeoutFailure(error),
    AuthRetryableFetchException() => NetworkFailure(error),
    AuthApiException() when AuthCodeFailure.of(error) != null =>
      AuthCodeFailure.of(error)!,
    AuthException() => UnauthorizedFailure(error),
    FunctionsFetchException() => NetworkFailure(error),
    FunctionException(:final status) when status == 401 || status == 403 =>
      UnauthorizedFailure(error),
    FunctionException(:final status) when status == 404 => NotFoundFailure(
      error,
    ),
    FunctionException(:final status) when status >= 500 => ServerFailure(error),
    FunctionException() => UnknownFailure(error),
    PostgrestException(code: 'P0001', message: 'plan_changed') =>
      PlanChangedFailure(error),
    PostgrestException(code: 'PGRST116') => NotFoundFailure(error),
    PostgrestException(code: '42501') => UnauthorizedFailure(error),
    PostgrestException(:final String code)
        when code.startsWith('22') || code == '54000' =>
      ValidationFailure(error),
    PostgrestException() => ServerFailure(error),
    FormatException() => ValidationFailure(error),
    _ => UnknownFailure(error),
  };
}

/// No internet or the host can't be reached.
final class NetworkFailure extends AppFailure {
  const new([super.cause]);

  @override
  bool get isRetryable => true;
}

final class TimeoutFailure extends AppFailure {
  const new([super.cause]);

  @override
  bool get isRetryable => true;
}

/// Not signed in, session expired, or not allowed (RLS).
final class UnauthorizedFailure extends AppFailure {
  const new([super.cause]);
}

final class NotFoundFailure extends AppFailure {
  const new([super.cause]);
}

/// Invalid input or data in an unexpected shape.
final class ValidationFailure extends AppFailure {
  const new([super.cause]);
}

final class ServerFailure extends AppFailure {
  const new([super.cause]);

  @override
  bool get isRetryable => true;
}

final class UnknownFailure extends AppFailure {
  const new([super.cause]);
}

/// Why a gym invite code was refused. None of them says whether a code ever
/// existed beyond these reasons (docs/decisions/gym_accounts.md §5).
enum InviteProblem {
  /// Unknown, damaged or not an Azm code.
  invalid,

  /// Past its 7 days, or revoked: either way the captain must make a new one.
  expired,

  /// Already used on another phone.
  used,

  /// This account cannot take this code (it is already in the gym, or the
  /// code no longer fits its member).
  conflict,

  /// Too many wrong tries: wait a few minutes.
  throttled,
}

final class InviteFailure extends AppFailure {
  const new(this.problem, [super.cause]);

  final InviteProblem problem;
}

/// Account deletion refused: the person is the only owner of these gyms,
/// which still have members. They hand the gym over or delete it first.
final class LastOwnerFailure extends AppFailure {
  const new(this.gymNames, [super.cause]);

  final List<String> gymNames;
}

/// The gym's plan changed on the server since this phone last saw it
/// (`save_plan` → `plan_changed`): the phone's edit was dropped, the captain's
/// version wins (docs/decisions/gym_accounts.md §11).
final class PlanChangedFailure extends AppFailure {
  const new([super.cause]);
}

/// What went wrong with an email code (sign-in for backup). One of three
/// things a person can act on; anything else is a normal failure.
enum AuthCodeProblem {
  /// The code is wrong or has expired (the server says the same for both).
  wrongOrExpired,

  /// Too many tries or too many emails: wait a little.
  tooMany,

  /// This email already belongs to another account (an anonymous gym
  /// account cannot take it: the person can sign in to that account instead).
  emailTaken,
}

final class AuthCodeFailure extends AppFailure {
  const new(this.problem, [super.cause]);

  final AuthCodeProblem problem;

  /// The problem a Supabase Auth error names, by its documented code
  /// (`otp_expired`, `over_email_send_rate_limit`, `email_exists`, 429).
  static AuthCodeFailure? of(AuthApiException error) {
    final code = error.code ?? '';
    final problem = switch (code) {
      'otp_expired' => AuthCodeProblem.wrongOrExpired,
      'over_email_send_rate_limit' ||
      'over_request_rate_limit' => AuthCodeProblem.tooMany,
      'email_exists' || 'identity_already_exists' => AuthCodeProblem.emailTaken,
      _ when error.statusCode == '429' => AuthCodeProblem.tooMany,
      _ => null,
    };
    return problem == null ? null : AuthCodeFailure(problem, error);
  }
}
