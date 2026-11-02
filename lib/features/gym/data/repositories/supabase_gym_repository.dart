import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/invite_code.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/install_id_store.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [GymRepository] on Supabase (docs/features/gym_accounts_backend.md).
///
/// A phone with no session signs in anonymously first (`signInAnonymously`),
/// then calls the `redeem_invite` Edge Function with the code and its install
/// id. Neither the code nor the install id is ever logged.
class SupabaseGymRepository implements GymRepository {
  const new(
    this._client,
    this._installId, {
    this.captchaToken,
    this.membershipRows,
    this.retries = 2,
  });

  final SupabaseClient _client;
  final InstallIdStore _installId;

  /// The seam for Cloudflare Turnstile (required before shipping, decision
  /// §16): returns the token for the anonymous sign-in. Null for now.
  final Future<String?> Function()? captchaToken;

  /// Reads the `memberships` rows; the default asks Supabase. Tests pass rows.
  final Future<List<Map<String, Object?>>> Function()? membershipRows;

  /// Network and server errors are tried again this many times.
  final int retries;

  @override
  Future<Result<JoinedGym>> redeem(InviteCode code) =>
      guard(() => _redeem(code, retried: false), retries: retries);

  Future<JoinedGym> _redeem(InviteCode code, {required bool retried}) async {
    await _ensureSession();
    final installId = await _installId.get();
    final Object? data;
    try {
      final response = await _client.functions.invoke(
        'redeem_invite',
        body: {'code': code.value, 'install_id': installId},
      );
      data = response.data;
    } on FunctionException catch (error) {
      // A stored anonymous session the server no longer knows (the account
      // was deleted): start over once with a fresh one. A permanent (email)
      // session is never replaced silently.
      if (error.status == 401 && !retried && _isAnonymous) {
        await _client.auth.signOut();
        return await _redeem(code, retried: true);
      }
      throw inviteFailureFor(error) ?? error;
    }
    if (data is! Map<String, Object?> || data['ok'] != true) {
      throw const FormatException('unexpected redeem answer');
    }
    return JoinedGym.fromJson(data);
  }

  bool get _isAnonymous => _client.auth.currentUser?.isAnonymous ?? false;

  Future<void> _ensureSession() async {
    if (_client.auth.currentSession != null) return;
    await _client.auth.signInAnonymously(
      captchaToken: await captchaToken?.call(),
    );
  }

  /// The failure for an `redeem_invite` answer, or null when the status says
  /// nothing about the code (401, 5xx, no connection): those stay generic.
  static InviteFailure? inviteFailureFor(FunctionException error) {
    final details = error.details;
    final reason = details is Map ? details['error'] : null;
    return switch (error.status) {
      400 || 404 => InviteFailure(InviteProblem.invalid, error),
      410 => InviteFailure(InviteProblem.expired, error),
      409 => InviteFailure(
        reason == 'conflict' ? InviteProblem.conflict : InviteProblem.used,
        error,
      ),
      429 => InviteFailure(InviteProblem.throttled, error),
      _ => null,
    };
  }

  /// Own rows only: row level security decides what comes back. `*` is
  /// avoided so a new column never reaches the phone by accident.
  @override
  Future<Result<List<Membership>>> loadMemberships() => guard(() async {
    if (_client.auth.currentSession == null) return const <Membership>[];
    final rows = await (membershipRows ?? _fetchRows)();
    return [for (final row in rows) Membership.fromJson(row)];
  }, retries: retries);

  Future<List<Map<String, Object?>>> _fetchRows() async {
    final rows = await _client
        .from('memberships')
        .select(
          'id, role, status, display_name, ended_at, can_edit_targets, '
          'can_edit_plan, can_build_own_plan, '
          'gyms(id, name, history_after_end)',
        )
        .order('joined_at');
    return [for (final row in rows) Map<String, Object?>.from(row)];
  }
}
