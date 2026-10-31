import 'dart:io';

import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/data/datasources/workout_remote.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';

PlanExercise testExercise(String id, int position) => PlanExercise(
  exerciseId: id,
  nameEn: id,
  nameAr: id,
  position: position,
  sets: 3,
  targetReps: 10,
  restSeconds: 90,
  weightStepKg: 2.5,
);

final testPlan = AssignedPlan(
  planId: 'plan',
  name: '5-day split',
  nextDayOrder: 1,
  days: [
    PlanDay(
      id: 'd1',
      planId: 'plan',
      dayOrder: 1,
      nameEn: 'Chest & Back',
      nameAr: 'بنش وضهر',
      exercises: [testExercise('bench', 1), testExercise('row', 2)],
    ),
    PlanDay(
      id: 'd2',
      planId: 'plan',
      dayOrder: 2,
      nameEn: 'Legs',
      nameAr: 'رجل',
      exercises: [testExercise('squat', 1)],
    ),
  ],
);

/// In-memory server. `offline = true` makes every call fail like no network.
class FakeRemote implements WorkoutRemote {
  bool offline = false;
  bool ready = true;
  AssignedPlan? plan = testPlan;
  List<LoggedSet> history = [];
  final calls = <String>[];
  final sets = <String, Map<String, dynamic>>{};

  @override
  Future<bool> ensureReady() async => ready; // signed in earlier

  void _check() {
    if (offline) throw const SocketException('offline');
  }

  @override
  Future<AssignedPlan?> fetchActivePlan() async {
    _check();
    return plan;
  }

  @override
  Future<List<LoggedSet>> fetchLastSets() async {
    _check();
    return history;
  }

  @override
  Future<void> insertSession(Map<String, dynamic> row) async {
    _check();
    calls.add('insert_session ${row['id']}');
  }

  @override
  Future<void> upsertSet(Map<String, dynamic> row) async {
    _check();
    calls.add('upsert_set ${row['id']}');
    sets[row['id'] as String] = row;
  }

  @override
  Future<void> deleteSet(String id) async {
    _check();
    calls.add('delete_set $id');
    sets.remove(id);
  }

  @override
  Future<int?> completeSession(String sessionId) async {
    _check();
    calls.add('complete_session $sessionId');
    return 2;
  }
}

/// Simple in-memory [WorkoutRepository] for controller and widget tests
/// (no database, no timers). Mirrors the offline repository's rules.
class FakeWorkoutRepository implements WorkoutRepository {
  new({this._plan, this.refreshResult});

  AssignedPlan? _plan;

  /// What [refreshPlan] returns; defaults to the current plan.
  Result<AssignedPlan?>? refreshResult;
  WorkoutSession? _open;
  final sets = <LoggedSet>[];
  final last = <String, List<LoggedSet>>{};
  int syncCalls = 0;
  var _ids = 0;

  @override
  Future<AssignedPlan?> cachedPlan() async => _plan;

  @override
  Future<Result<AssignedPlan?>> refreshPlan() async =>
      refreshResult ?? Success(_plan);

  @override
  Future<WorkoutSession?> openSession() async => _open;

  @override
  Future<Map<String, List<LoggedSet>>> lastSets(
    Iterable<String> exerciseIds,
  ) async => {
    for (final id in exerciseIds)
      if (last[id] != null) id: last[id]!,
  };

  @override
  Future<List<LoggedSet>> setsOf(String sessionId) async =>
      sets.where((s) => s.sessionId == sessionId).toList();

  @override
  Future<WorkoutSession> startSession(PlanDay day) async =>
      _open = WorkoutSession(
        id: 's${_ids++}',
        planDayId: day.id,
        startedAt: DateTime(2026),
      );

  @override
  Future<LoggedSet> logSet({
    required String sessionId,
    required String exerciseId,
    required int setNumber,
    required double weightKg,
    required int reps,
  }) async {
    final set = LoggedSet(
      id: 'set${_ids++}',
      sessionId: sessionId,
      exerciseId: exerciseId,
      setNumber: setNumber,
      weightKg: weightKg,
      reps: reps,
      loggedAt: DateTime(2026),
    );
    sets.add(set);
    return set;
  }

  @override
  Future<void> updateSet(LoggedSet set) async {}

  @override
  Future<void> deleteSet(String setId) async =>
      sets.removeWhere((s) => s.id == setId);

  @override
  Future<AssignedPlan?> completeSession(String sessionId) async {
    final plan = _plan;
    final open = _open;
    _open = null;
    if (plan == null || open == null) return plan;
    final day = plan.days.firstWhere((d) => d.id == open.planDayId);
    return _plan = plan.copyWith(nextDayOrder: plan.dayAfter(day.dayOrder));
  }

  @override
  Stream<int> watchPendingCount() => Stream.value(0);

  @override
  Future<Result<int>> sync() async {
    syncCalls++;
    return const Success(0);
  }
}
