import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/invite_code.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/usecases/redeem_invite.dart';
import 'package:gym_tracker/features/gym/presentation/gym_providers.dart';

/// How the code reached the app. Only the way is sent to analytics, never the
/// code.
enum JoinVia { scan, link, code }

sealed class JoinState {
  const new();
}

final class JoinIdle extends JoinState {
  const new();
}

final class JoinSubmitting extends JoinState {
  const new();
}

final class JoinRefused extends JoinState {
  const new(this.failure);

  final AppFailure failure;
}

final class JoinDone extends JoinState {
  const new(this.joined);

  final JoinedGym joined;
}

final NotifierProvider<JoinController, JoinState> joinControllerProvider =
    NotifierProvider<JoinController, JoinState>(JoinController.new);

/// Redeems a code. One try at a time: a second tap while the first is on its
/// way does nothing.
class JoinController extends Notifier<JoinState> {
  @override
  JoinState build() => const JoinIdle();

  Future<void> redeem(InviteCode code, {required JoinVia via}) async {
    if (state is JoinSubmitting) return;
    state = const JoinSubmitting();
    unawaited(Analytics.capture('gym_join_started', {'via': via.name}));
    final result = await RedeemInvite(
      ref.read(gymRepositoryProvider),
      ref.read(gymLocalRepositoryProvider),
    )(code);
    if (!ref.mounted) return;
    switch (result) {
      case Success(:final value):
        unawaited(Analytics.capture('gym_joined', {'via': via.name}));
        ref.invalidate(gymControllerProvider);
        state = JoinDone(value);
      case Failed(:final failure):
        unawaited(
          Analytics.capture('gym_join_failed', {'reason': reasonOf(failure)}),
        );
        state = JoinRefused(failure);
    }
  }

  /// Back to the start (after the member read an error).
  void reset() {
    if (state is! JoinSubmitting) state = const JoinIdle();
  }

  /// A fixed word for analytics: never the failure's text or cause.
  static String reasonOf(AppFailure failure) => switch (failure) {
    InviteFailure(:final problem) => problem.name,
    NetworkFailure() || TimeoutFailure() => 'offline',
    _ => 'error',
  };
}
