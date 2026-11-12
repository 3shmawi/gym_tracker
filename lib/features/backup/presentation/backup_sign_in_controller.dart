import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/backup/domain/usecases/email_rules.dart';
import 'package:gym_tracker/features/backup/presentation/backup_sync.dart';
import 'package:gym_tracker/features/gym/presentation/gym_providers.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:meta/meta.dart';

enum BackupStep { email, code, done }

/// What the person can act on; shown as a line under the field.
enum BackupProblem {
  invalidEmail,
  invalidCode,
  wrongOrExpired,
  tooMany,
  emailTaken,
  offline,
  server,
}

@immutable
class BackupSignInState {
  const new({
    this.step = BackupStep.email,
    this.email = '',
    this.busy = false,
    this.problem,
    this.resendAt,
  });

  final BackupStep step;
  final String email;
  final bool busy;
  final BackupProblem? problem;

  /// A new code may be asked for from this time (Supabase allows one email
  /// per 60 seconds).
  final DateTime? resendAt;

  BackupSignInState copyWith({
    BackupStep? step,
    String? email,
    bool? busy,
    BackupProblem? Function()? problem,
    DateTime? Function()? resendAt,
  }) => BackupSignInState(
    step: step ?? this.step,
    email: email ?? this.email,
    busy: busy ?? this.busy,
    problem: problem == null ? this.problem : problem(),
    resendAt: resendAt == null ? this.resendAt : resendAt(),
  );
}

/// The sign-in by email code that turns backup on (docs/designs/
/// never_lose_history.md §2). One screen serves new and returning people: a
/// known email signs in, a new one makes an account, and the app never says
/// which. A gym trainee (anonymous) keeps the same account: the code
/// confirms their email.
final NotifierProvider<BackupSignInController, BackupSignInState>
backupSignInProvider =
    NotifierProvider.autoDispose<BackupSignInController, BackupSignInState>(
      BackupSignInController.new,
    );

class BackupSignInController extends Notifier<BackupSignInState> {
  static const resendAfter = Duration(seconds: 60);

  @override
  BackupSignInState build() => const BackupSignInState();

  DateTime _now() => ref.read(clockProvider)();

  /// Seconds until a new code may be asked for (0 = now).
  int resendIn() {
    final at = state.resendAt;
    if (at == null) return 0;
    final left = (at.difference(_now()).inMilliseconds / 1000).ceil();
    return left.clamp(0, resendAfter.inSeconds);
  }

  Future<void> submitEmail(String raw) async {
    if (state.busy) return;
    final email = EmailRules.clean(raw);
    if (email == null) {
      state = state.copyWith(problem: () => BackupProblem.invalidEmail);
      return;
    }
    await _send(email, first: true);
  }

  Future<void> resend() async {
    if (state.busy || resendIn() > 0) return;
    await _send(state.email, first: false);
  }

  Future<void> _send(String email, {required bool first}) async {
    state = state.copyWith(busy: true, email: email, problem: () => null);
    if (first) unawaited(Analytics.capture('backup_sign_in_started'));
    final result = await ref.read(accountRepositoryProvider).sendCode(email);
    if (!ref.mounted) return;
    switch (result) {
      case Success():
        state = state.copyWith(
          busy: false,
          step: BackupStep.code,
          resendAt: () => _now().add(resendAfter),
        );
      case Failed(:final failure):
        state = state.copyWith(busy: false, problem: () => _problemOf(failure));
    }
  }

  Future<void> submitCode(String raw) async {
    if (state.busy) return;
    final code = EmailRules.code(raw);
    if (!EmailRules.isCode(code)) {
      state = state.copyWith(problem: () => BackupProblem.invalidCode);
      return;
    }
    state = state.copyWith(busy: true, problem: () => null);
    final result = await ref
        .read(accountRepositoryProvider)
        .verifyCode(state.email, code);
    if (!ref.mounted) return;
    switch (result) {
      case Success():
        // Signed in with an email: backup starts, and the first run sends
        // the whole history.
        await ref.read(backupSyncProvider).enable();
        if (!ref.mounted) return;
        state = state.copyWith(busy: false, step: BackupStep.done);
      case Failed(:final failure):
        final problem = _problemOf(failure);
        unawaited(
          Analytics.capture('backup_code_failed', {'reason': problem.name}),
        );
        state = state.copyWith(busy: false, problem: () => problem);
    }
  }

  /// The email belongs to another account: sign in to that one. A gym trainee
  /// account cannot be merged, so this phone leaves it (the gym needs a new
  /// code from the captain); nothing on the phone is deleted.
  Future<void> useExistingAccount() async {
    if (state.busy || state.problem != BackupProblem.emailTaken) return;
    state = state.copyWith(busy: true, problem: () => null);
    final signedOut = await ref.read(accountRepositoryProvider).signOut();
    if (!ref.mounted) return;
    if (signedOut is Failed<void>) {
      state = state.copyWith(
        busy: false,
        problem: () => _problemOf(signedOut.failure),
      );
      return;
    }
    await _send(state.email, first: false);
  }

  void changeEmail() => state = state.copyWith(
    step: BackupStep.email,
    problem: () => null,
    resendAt: () => null,
  );

  static BackupProblem _problemOf(AppFailure failure) => switch (failure) {
    NetworkFailure() || TimeoutFailure() => BackupProblem.offline,
    AuthCodeFailure(:final problem) => switch (problem) {
      AuthCodeProblem.wrongOrExpired => BackupProblem.wrongOrExpired,
      AuthCodeProblem.tooMany => BackupProblem.tooMany,
      AuthCodeProblem.emailTaken => BackupProblem.emailTaken,
    },
    ValidationFailure() => BackupProblem.invalidEmail,
    _ => BackupProblem.server,
  };
}
