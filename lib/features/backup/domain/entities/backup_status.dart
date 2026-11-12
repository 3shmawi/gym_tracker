import 'package:meta/meta.dart';

/// Where backing up stands, for the Settings card (never an error screen:
/// the training is safe on the phone in every state).
enum BackupState {
  /// The member has not turned backup on.
  off,

  /// Everything is on the account.
  upToDate,

  /// Some workouts wait for the network (or the next try).
  waiting,

  /// The server refused something it will keep refusing; see
  /// [BackupStatus.problems].
  failed,

  /// The session ended (revoked or expired): sign in again to go on.
  signInAgain,
}

@immutable
class BackupStatus {
  const new({
    required this.state,
    this.pending = 0,
    this.problems = 0,
    this.lastSyncedAt,
    this.planConflict = false,
  });

  static const off = BackupStatus(state: BackupState.off);

  final BackupState state;

  /// Workouts not on the account yet.
  final int pending;

  /// Workouts the server refused (they stay on the phone).
  final int problems;
  final DateTime? lastSyncedAt;

  /// The plan on the account was changed on another phone: this phone's plan
  /// was not uploaded (restore asks which to keep).
  final bool planConflict;

  @override
  bool operator ==(Object other) =>
      other is BackupStatus &&
      other.state == state &&
      other.pending == pending &&
      other.problems == problems &&
      other.lastSyncedAt == lastSyncedAt &&
      other.planConflict == planConflict;

  @override
  int get hashCode =>
      Object.hash(state, pending, problems, lastSyncedAt, planConflict);
}
