import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/backup/domain/repositories/backup_repositories.dart';
import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';

/// Before the backend is ready (and in widget tests): every call says the
/// session is not allowed, so nothing runs.
class UnconfiguredBackupRemote implements BackupRemote {
  const new();

  static const _no = Failed<Never>(UnauthorizedFailure());

  @override
  Future<Result<void>> ensurePerson() async => _no;

  @override
  Future<Result<void>> uploadSessions(List<WorkoutSession> sessions) async =>
      _no;

  @override
  Future<Result<int>> savePlan(int baseVersion, WorkoutPlan plan) async => _no;

  @override
  Future<Result<void>> saveState(Level bestLevel, ChosenDay? chosenDay) async =>
      _no;
}

/// No database (the preferences are in use): nothing can be queued.
class EmptyBackupQueue implements BackupQueue {
  const new();

  @override
  Future<List<WorkoutSession>> pending(int limit) async => const [];

  @override
  Future<void> markSynced(Iterable<String> clientIds) async {}

  @override
  Future<void> markProblem(String clientId, String reason) async {}

  @override
  Future<int> pendingCount() async => 0;

  @override
  Future<int> problemCount() async => 0;
}

/// [BackupSettings] in memory (tests, and before the phone's storage is up).
class InMemoryBackupSettings implements BackupSettings {
  new({
    this.enabled = false,
    this.lastSyncedAt,
    this.planVersion = 0,
    this.planFingerprint,
    this.planConflict = false,
    this.stateFingerprint,
  });

  @override
  bool enabled;
  @override
  DateTime? lastSyncedAt;
  @override
  int planVersion;
  @override
  String? planFingerprint;
  @override
  bool planConflict;
  @override
  String? stateFingerprint;

  @override
  Future<void> setEnabled({required bool value}) async => enabled = value;

  @override
  Future<void> setLastSyncedAt(DateTime at) async => lastSyncedAt = at;

  @override
  Future<void> setPlan({
    required int version,
    required String fingerprint,
  }) async {
    planVersion = version;
    planFingerprint = fingerprint;
  }

  @override
  Future<void> setPlanConflict({required bool value}) async =>
      planConflict = value;

  @override
  Future<void> setStateFingerprint(String fingerprint) async =>
      stateFingerprint = fingerprint;
}
