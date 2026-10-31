import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/data/datasources/workout_database.dart';
import 'package:gym_tracker/features/workout/data/datasources/workout_remote.dart';
import 'package:gym_tracker/features/workout/data/repositories/offline_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout.dart';

PlanExercise _exercise(String id, int position) => PlanExercise(
  exerciseId: id,
  nameEn: id,
  nameAr: id,
  position: position,
  sets: 3,
  targetReps: 10,
  restSeconds: 90,
  weightStepKg: 2.5,
);

final _plan = AssignedPlan(
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
      exercises: [_exercise('bench', 1), _exercise('row', 2)],
    ),
    PlanDay(
      id: 'd2',
      planId: 'plan',
      dayOrder: 2,
      nameEn: 'Legs',
      nameAr: 'رجل',
      exercises: [_exercise('squat', 1)],
    ),
  ],
);

/// In-memory server. `offline = true` makes every call fail like no network.
class FakeRemote implements WorkoutRemote {
  bool offline = false;
  bool ready = true;
  AssignedPlan? plan = _plan;
  List<LoggedSet> history = [];
  final calls = <String>[];
  final sets = <String, Map<String, dynamic>>{};

  @override
  bool get isReady => ready;

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

void main() {
  late WorkoutDatabase db;
  late FakeRemote remote;
  late OfflineWorkoutRepository repo;
  var ids = 0;
  var clock = DateTime(2026, 11);

  setUp(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
    db = WorkoutDatabase(NativeDatabase.memory());
    remote = FakeRemote();
    ids = 0;
    clock = DateTime(2026, 11);
    repo = OfflineWorkoutRepository(
      db: db,
      remote: remote,
      newId: () => 'id${ids++}',
      now: () => clock = clock.add(const Duration(minutes: 1)),
    );
  });

  tearDown(() => db.close());

  Future<int> pending() => repo.watchPendingCount().first;

  test('refreshPlan caches the plan for offline use', () async {
    final result = await repo.refreshPlan();

    expect(result, isA<Success<AssignedPlan?>>());
    final cached = await repo.cachedPlan();
    expect(cached?.days.map((d) => d.id), ['d1', 'd2']);
    expect(cached?.nextDay?.id, 'd1');
    expect(cached?.days.first.exercises.first.nameAr, 'bench');
  });

  test('refreshPlan offline keeps the cache and reports a failure', () async {
    await repo.refreshPlan();
    remote.offline = true;

    final result = await repo.refreshPlan();

    expect(result, isA<Failed<AssignedPlan?>>());
    expect((await repo.cachedPlan())?.planId, 'plan');
  });

  test('a full offline session is queued and synced in order', () async {
    await repo.refreshPlan();
    remote.offline = true;

    final session = await repo.startSession(_plan.days.first);
    final set1 = await repo.logSet(
      sessionId: session.id,
      exerciseId: 'bench',
      setNumber: 1,
      weightKg: 40,
      reps: 10,
    );
    final next = await repo.completeSession(session.id);

    expect(next?.nextDay?.id, 'd2', reason: 'plan moves on at once, offline');
    expect(await pending(), 3);
    expect(await repo.sync(), isA<Failed<int>>());
    expect(await pending(), 3, reason: 'nothing lost while offline');

    remote.offline = false;
    final synced = await repo.sync();

    expect(synced, isA<Success<int>>());
    expect((synced as Success<int>).value, 3);
    expect(remote.calls, [
      'insert_session ${session.id}',
      'upsert_set ${set1.id}',
      'complete_session ${session.id}',
    ]);
    expect(await pending(), 0);
  });

  test('completing twice moves the plan only once', () async {
    await repo.refreshPlan();
    final session = await repo.startSession(_plan.days.first);

    await repo.completeSession(session.id);
    final again = await repo.completeSession(session.id);

    expect(again?.nextDayOrder, 2);
  });

  test('after the last day the plan wraps to day 1', () async {
    remote.plan = _plan.copyWith(nextDayOrder: 2);
    await repo.refreshPlan();
    final session = await repo.startSession(_plan.days.last);

    final next = await repo.completeSession(session.id);

    expect(next?.nextDayOrder, 1);
  });

  test('missing a day does not skip a workout', () async {
    await repo.refreshPlan();
    clock = clock.add(const Duration(days: 3));

    expect((await repo.cachedPlan())?.nextDay?.id, 'd1');
  });

  test('lastSets returns the newest completed session per exercise', () async {
    await repo.refreshPlan();
    final old = await repo.startSession(_plan.days.first);
    await repo.logSet(
      sessionId: old.id,
      exerciseId: 'bench',
      setNumber: 1,
      weightKg: 35,
      reps: 10,
    );
    await repo.completeSession(old.id);

    final recent = await repo.startSession(_plan.days.first);
    await repo.logSet(
      sessionId: recent.id,
      exerciseId: 'bench',
      setNumber: 1,
      weightKg: 40,
      reps: 10,
    );
    await repo.logSet(
      sessionId: recent.id,
      exerciseId: 'bench',
      setNumber: 2,
      weightKg: 40,
      reps: 8,
    );

    var last = await repo.lastSets(['bench']);
    expect(last['bench']?.map((s) => s.weightKg), [
      35,
    ], reason: 'the open session is not "last time" yet');

    await repo.completeSession(recent.id);
    last = await repo.lastSets(['bench', 'row']);

    expect(last['bench']?.map((s) => (s.weightKg, s.reps)), [
      (40, 10),
      (40, 8),
    ]);
    expect(last.containsKey('row'), isFalse);
  });

  test('history from the server is used on a new device', () async {
    remote.history = [
      LoggedSet(
        id: 'server-set',
        sessionId: 'server-session',
        exerciseId: 'row',
        setNumber: 1,
        weightKg: 55,
        reps: 12,
        loggedAt: DateTime(2026, 10),
      ),
    ];

    await repo.refreshPlan();

    final last = await repo.lastSets(['row']);
    expect(last['row']?.single.weightKg, 55);
  });

  test('editing and deleting a set are synced too', () async {
    await repo.refreshPlan();
    final session = await repo.startSession(_plan.days.first);
    final set = await repo.logSet(
      sessionId: session.id,
      exerciseId: 'bench',
      setNumber: 1,
      weightKg: 40,
      reps: 10,
    );
    final fixed = LoggedSet(
      id: set.id,
      sessionId: set.sessionId,
      exerciseId: set.exerciseId,
      setNumber: 1,
      weightKg: 42.5,
      reps: 10,
      loggedAt: set.loggedAt,
    );
    await repo.updateSet(fixed);
    expect((await repo.setsOf(session.id)).single.weightKg, 42.5);

    await repo.sync();
    expect(remote.sets[set.id]?['weight_kg'], 42.5);

    await repo.deleteSet(set.id);
    await repo.sync();
    expect(await repo.setsOf(session.id), isEmpty);
    expect(remote.sets, isEmpty);
  });

  test(
    'a write rejected by the server is dropped after max attempts',
    () async {
      final rejecting = _RejectingRemote();
      repo = OfflineWorkoutRepository(
        db: db,
        remote: rejecting,
        newId: () => 'id${ids++}',
      );
      await repo.startSession(_plan.days.first);

      for (var i = 1; i < OfflineWorkoutRepository.maxAttempts; i++) {
        expect(await repo.sync(), isA<Failed<int>>());
        expect(await pending(), 1);
      }
      expect(await repo.sync(), isA<Success<int>>());
      expect(await pending(), 0);
    },
  );

  test('nothing is pushed until the user is signed in', () async {
    remote.ready = false;
    final session = await repo.startSession(_plan.days.first);

    expect(await repo.sync(), const TypeMatcher<Success<int>>());
    expect(remote.calls, isEmpty);
    expect(await pending(), 1);

    remote.ready = true;
    await repo.sync();
    expect(remote.calls, ['insert_session ${session.id}']);
  });
}

class _RejectingRemote extends FakeRemote {
  @override
  Future<void> insertSession(Map<String, dynamic> row) async =>
      throw const FormatException('rejected');
}
