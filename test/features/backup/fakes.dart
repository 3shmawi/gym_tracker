import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/backup/domain/repositories/backup_repositories.dart';
import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';

/// A model of the account on the server (migration 0022): workouts keyed by
/// content hash, the plan saved first wins, the level only goes up, the
/// chosen day is the last write. One server, several phones.
class FakeServer {
  final Map<String, WorkoutSession> sessions = {};
  WorkoutPlan? plan;
  int planVersion = 0;
  Level bestLevel = Level.beginner;
  ChosenDay? chosenDay;

  /// Ids the server will always refuse (a rule: out of range, over the cap).
  final Set<String> refused = {};
  AppFailure? failWith;
  int uploadCalls = 0;
  int planCalls = 0;
  int stateCalls = 0;
  final List<int> chunkSizes = [];

  // The remote this phone talks to.
  // ignore: use_to_and_as_if_applicable, a phone's connection, not a conversion.
  BackupRemote phone() => _Remote(this);
}

class _Remote implements BackupRemote {
  new(this.server);

  final FakeServer server;

  Result<T>? _down<T>() =>
      server.failWith == null ? null : Failed<T>(server.failWith!);

  @override
  Future<Result<void>> ensurePerson() async =>
      _down<void>() ?? const Success(null);

  @override
  Future<Result<void>> uploadSessions(List<WorkoutSession> sessions) async {
    server.uploadCalls++;
    final down = _down<void>();
    if (down != null) return down;
    server.chunkSizes.add(sessions.length);
    // The server refuses a whole request when one row is not allowed.
    if (sessions.any((s) => server.refused.contains(s.clientId))) {
      return const Failed(ValidationFailure());
    }
    for (final s in sessions) {
      server.sessions.putIfAbsent(s.clientId, () => s);
    }
    return const Success(null);
  }

  @override
  Future<Result<int>> savePlan(int baseVersion, WorkoutPlan plan) async {
    server.planCalls++;
    final down = _down<int>();
    if (down != null) return down;
    if (baseVersion != server.planVersion) {
      return const Failed(PlanChangedFailure());
    }
    if (server.plan?.toJson().toString() != plan.toJson().toString()) {
      server
        ..plan = plan
        ..planVersion += 1;
    }
    return Success(server.planVersion);
  }

  @override
  Future<Result<void>> saveState(Level bestLevel, ChosenDay? chosenDay) async {
    server.stateCalls++;
    final down = _down<void>();
    if (down != null) return down;
    if (bestLevel.index > server.bestLevel.index) server.bestLevel = bestLevel;
    server.chosenDay = chosenDay;
    return const Success(null);
  }
}

/// A phone's queue of solo workouts, in memory.
class FakeQueue implements BackupQueue {
  final List<WorkoutSession> all = [];
  final Set<String> synced = {};
  final Map<String, String> problems = {};

  List<WorkoutSession> get _waiting => [
    for (final s in all)
      if (!synced.contains(s.clientId) && !problems.containsKey(s.clientId)) s,
  ]..sort((a, b) => a.finishedAt.compareTo(b.finishedAt));

  @override
  Future<List<WorkoutSession>> pending(int limit) async =>
      _waiting.take(limit).toList();

  @override
  Future<void> markSynced(Iterable<String> clientIds) async =>
      synced.addAll(clientIds);

  @override
  Future<void> markProblem(String clientId, String reason) async =>
      problems[clientId] = reason;

  @override
  Future<int> pendingCount() async => _waiting.length;

  @override
  Future<int> problemCount() async => problems.length;
}
