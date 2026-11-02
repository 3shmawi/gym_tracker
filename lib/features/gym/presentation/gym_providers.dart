import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/account_session.dart';
import 'package:gym_tracker/features/gym/domain/entities/workspace.dart';
import 'package:gym_tracker/features/gym/domain/repositories/account_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_local_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_repository.dart';
import 'package:gym_tracker/features/gym/domain/usecases/end_account.dart';
import 'package:gym_tracker/features/gym/domain/usecases/refresh_memberships.dart';
import 'package:gym_tracker/features/gym/domain/usecases/switch_workspace.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';

/// Override in tests: `gymRepositoryProvider.overrideWithValue(fake)`.
final gymRepositoryProvider = Provider<GymRepository>(
  (ref) => Dependencies.gymRepository,
);
final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => Dependencies.accountRepository,
);
final gymLocalRepositoryProvider = Provider<GymLocalRepository>(
  (ref) => Dependencies.gymLocalRepository,
);

/// Who is signed in. Follows the repository's changes, including the server
/// refusing to refresh a session (revoked, expired, deleted): the person is
/// then solo again.
final accountSessionProvider =
    NotifierProvider<AccountSessionNotifier, AccountSession>(
      AccountSessionNotifier.new,
    );

class AccountSessionNotifier extends Notifier<AccountSession> {
  @override
  AccountSession build() {
    final account = ref.watch(accountRepositoryProvider);
    final local = ref.watch(gymLocalRepositoryProvider);
    final sub = account.sessionChanges.listen((next) {
      final wasSignedIn = state.isSignedIn;
      state = next;
      // The gym state rebuilds by itself (it watches this provider, and is
      // empty while signed out); only the phone's copy needs clearing.
      if (wasSignedIn && !next.isSignedIn) {
        unawaited(HandleSessionEnded(local)());
      }
    });
    ref.onDispose(() => unawaited(sub.cancel()));
    return account.session;
  }
}

/// The active workspace and the gyms to pick from. Starts from the phone's
/// copy (works offline), then asks the server when someone is signed in.
final gymControllerProvider = AsyncNotifierProvider<GymController, GymSnapshot>(
  GymController.new,
  retry: (_, _) => null,
);

class GymController extends AsyncNotifier<GymSnapshot> {
  GymLocalRepository get _local => ref.read(gymLocalRepositoryProvider);

  @override
  Future<GymSnapshot> build() async {
    final session = ref.watch(accountSessionProvider);
    final cached = await LoadGymSnapshot(_local)();
    if (!session.isSignedIn) return const GymSnapshot();
    // After the first state is out, so the screen is never held back by the
    // network.
    unawaited(Future<void>.microtask(refresh));
    return cached;
  }

  /// Asks the server; offline keeps what the phone has. Returns the failure
  /// so a screen can say "couldn't refresh".
  Future<AppFailure?> refresh() async {
    final result = await RefreshMemberships(
      ref.read(gymRepositoryProvider),
      _local,
    )();
    if (!ref.mounted) return null;
    switch (result) {
      case Success(:final value):
        state = AsyncData(value);
        return null;
      case Failed(:final failure):
        return failure;
    }
  }

  /// Picks where to train. Returns false when the target is not allowed
  /// (not an active membership) or could not be saved.
  Future<bool> switchTo(Workspace target) async {
    final current = state.value ?? const GymSnapshot();
    final result = await SwitchWorkspace(_local)(target, current);
    if (!ref.mounted) return false;
    switch (result) {
      case Success(:final value):
        state = AsyncData(value);
        unawaited(
          Analytics.capture('gym_switched', {
            'to': target is GymWorkspace ? 'gym' : 'solo',
          }),
        );
        return true;
      case Failed():
        return false;
    }
  }
}

/// Signs out, and deletes the account.
final accountActionsProvider = Provider<AccountActions>(AccountActions.new);

class AccountActions {
  const new(this._ref);

  final Ref _ref;

  Future<Result<void>> signOut() async {
    final result = await SignOut(
      _ref.read(accountRepositoryProvider),
      _ref.read(gymLocalRepositoryProvider),
    )();
    if (result is Success<void>) {
      unawaited(Analytics.capture('account_signed_out'));
      // Analytics.reset() makes a new anonymous id for the next person.
      unawaited(Analytics.reset());
      _ref.invalidate(gymControllerProvider);
    }
    return result;
  }

  Future<Result<void>> addEmail(String email) =>
      _ref.read(accountRepositoryProvider).addEmail(email);

  Future<Result<void>> deleteAccount({required bool eraseLocalWorkouts}) async {
    final result = await DeleteAccount(
      _ref.read(accountRepositoryProvider),
      _ref.read(gymLocalRepositoryProvider),
      _ref.read(workoutRepositoryProvider),
    )(eraseLocalWorkouts: eraseLocalWorkouts);
    if (result is Success<void>) {
      unawaited(Analytics.capture('account_deleted'));
      unawaited(Analytics.reset());
      _ref.invalidate(gymControllerProvider);
      if (eraseLocalWorkouts) _ref.invalidate(nextWorkoutControllerProvider);
    }
    return result;
  }
}
