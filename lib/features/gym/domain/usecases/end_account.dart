import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/repositories/account_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_local_repository.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';

/// Signs out: the session ends on this phone and the workspace goes back to
/// solo. Solo workouts on the phone are not touched.
class SignOut {
  const new(this._account, this._local);

  final AccountRepository _account;
  final GymLocalRepository _local;

  Future<Result<void>> call() async {
    final result = await _account.signOut();
    if (result is Success<void>) await _local.clear();
    return result;
  }
}

/// The session was ended from outside (the server refused to refresh it:
/// revoked, expired, deleted): the person is solo again.
class HandleSessionEnded {
  const new(this._local);

  final GymLocalRepository _local;

  Future<void> call() async {
    await _local.clear();
  }
}

/// Deletes the account on the server (Apple 5.1.1(v), Google Play), then the
/// phone's gym state; with `eraseLocalWorkouts` also this phone's history.
class DeleteAccount {
  const new(this._account, this._local, this._workouts);

  final AccountRepository _account;
  final GymLocalRepository _local;
  final WorkoutRepository _workouts;

  Future<Result<void>> call({required bool eraseLocalWorkouts}) async {
    final result = await _account.deleteAccount();
    if (result is! Success<void>) return result;
    await _local.clear();
    if (eraseLocalWorkouts) await _workouts.clearHistory();
    return result;
  }
}
