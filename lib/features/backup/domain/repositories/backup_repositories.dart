import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/backup/domain/entities/restore.dart';
import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';

/// The member's own account on the server (migration 0022). Every call is
/// safe to repeat.
abstract interface class BackupRemote {
  /// Gives the signed-in account its person (creating it for a permanent
  /// session without a gym) and says whether the account can be written to.
  Future<Result<void>> ensurePerson();

  /// Stores up to 50 **solo** workouts; ones the server has (same
  /// `clientId`) are not stored again.
  Future<Result<void>> uploadSessions(List<WorkoutSession> sessions);

  /// Saves the plan on top of [baseVersion] (0 = none yet) and returns the
  /// new version. `PlanChangedFailure` when the account's plan is newer:
  /// the plan saved first wins.
  Future<Result<int>> savePlan(int baseVersion, WorkoutPlan plan);

  /// Saves the best level (it only goes up on the server) and the chosen
  /// day (the last write wins).
  Future<Result<void>> saveState(Level bestLevel, ChosenDay? chosenDay);

  /// The next page of the account's workouts after [after] (null = from the
  /// start), oldest first. Rows the app cannot read are skipped and counted.
  Future<Result<RestorePage>> fetchSessions({
    RestoreCursor? after,
    int limit = 200,
  });

  /// The account's plan, or null when it has none.
  Future<Result<RemotePlan?>> fetchPlan();

  /// The account's best level and chosen day, or null when it has none.
  Future<Result<RemoteState?>> fetchState();
}

/// The workouts waiting on the phone. Only **solo** workouts: a gym workout
/// goes up through the gym's outbox.
abstract interface class BackupQueue {
  /// Solo workouts not backed up and not refused, oldest first.
  Future<List<WorkoutSession>> pending(int limit);

  Future<void> markSynced(Iterable<String> clientIds);

  /// The server will not take this workout (kept on the phone).
  Future<void> markProblem(String clientId, String reason);

  Future<int> pendingCount();
  Future<int> problemCount();
}

/// What the phone remembers about backing up.
abstract interface class BackupSettings {
  bool get enabled;
  Future<void> setEnabled({required bool value});

  DateTime? get lastSyncedAt;
  Future<void> setLastSyncedAt(DateTime at);

  /// The account's plan version this phone last uploaded or took, and the
  /// fingerprint of the plan that was uploaded (so an unchanged plan is not
  /// sent again).
  int get planVersion;
  String? get planFingerprint;
  Future<void> setPlan({required int version, required String fingerprint});

  /// The account holds a newer plan than this phone's (see `BackupStatus`).
  bool get planConflict;
  Future<void> setPlanConflict({required bool value});

  /// Fingerprint of the level and chosen day last uploaded.
  String? get stateFingerprint;
  Future<void> setStateFingerprint(String fingerprint);

  /// Where the download of the account's workouts stopped (`RestoreCursor`
  /// text; `done` once everything was taken; null = not started).
  String? get restoreCursor;
  Future<void> setRestoreCursor(String? value);

  /// The plan that lost a conflict, kept for 30 days (JSON text and when).
  String? get keptPlan;
  DateTime? get keptPlanAt;
  Future<void> setKeptPlan(String? json, DateTime at);
}
