import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:gym_tracker/core/monitoring/monitoring.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/data/datasources/workout_database.dart';
import 'package:gym_tracker/features/workout/data/datasources/workout_remote.dart';
import 'package:gym_tracker/features/workout/data/models/workout_json.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';

/// Kinds of queued writes, replayed in order by
/// [OfflineWorkoutRepository.sync].
abstract final class OutboxKind {
  static const insertSession = 'insert_session';
  static const upsertSet = 'upsert_set';
  static const deleteSet = 'delete_set';
  static const completeSession = 'complete_session';
}

/// Offline-first [WorkoutRepository]: reads and writes go to the device
/// database; writes are also queued in the outbox and pushed by [sync].
class OfflineWorkoutRepository implements WorkoutRepository {
  new({
    required this._db,
    required this._remote,
    required this._newId,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final WorkoutDatabase _db;
  final WorkoutRemote _remote;
  final String Function() _newId;
  final DateTime Function() _now;

  static const _planKey = 'plan';

  /// A write that keeps failing for a non-network reason (e.g. rejected by
  /// RLS) is dropped after this many tries so it can't block the queue.
  static const maxAttempts = 5;

  bool _syncing = false;

  // ---------------------------------------------------------------- plan --

  @override
  Future<AssignedPlan?> cachedPlan() async {
    final row = await (_db.select(
      _db.cacheEntries,
    )..where((t) => t.key.equals(_planKey))).getSingleOrNull();
    if (row == null) return null;
    final json = jsonDecode(row.value) as Map<String, dynamic>;
    return WorkoutJson.planFromAssignment(json);
  }

  Future<void> _cachePlan(AssignedPlan plan) => _db
      .into(_db.cacheEntries)
      .insertOnConflictUpdate(
        CacheEntriesCompanion.insert(
          key: _planKey,
          value: jsonEncode(WorkoutJson.planToAssignment(plan)),
        ),
      );

  @override
  Future<Result<AssignedPlan?>> refreshPlan() async {
    if (!await _remote.ensureReady()) return Success(await cachedPlan());
    // Push local changes first, so the server's next day already includes
    // sessions completed offline.
    final pushed = await sync();
    if (pushed case Failed(:final failure)) return Failed(failure);

    final result = await guard(() async {
      final plan = await _remote.fetchActivePlan();
      final history = await _remote.fetchLastSets();
      return (plan, history);
    });
    switch (result) {
      case Failed(:final failure):
        return Failed(failure);
      case Success(value: (final plan, final history)):
        await _db.transaction(() async {
          if (plan == null) {
            await (_db.delete(
              _db.cacheEntries,
            )..where((t) => t.key.equals(_planKey))).go();
          } else {
            await _cachePlan(plan);
          }
          await _db.batch((b) {
            b.insertAllOnConflictUpdate(_db.localSets, [
              for (final s in history) _setCompanion(s),
            ]);
          });
        });
        return Success(plan);
    }
  }

  // ------------------------------------------------------------ sessions --

  @override
  Future<WorkoutSession?> openSession() async {
    final row =
        await (_db.select(_db.localSessions)
              ..where((t) => t.status.equals('in_progress'))
              ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _session(row);
  }

  @override
  Future<WorkoutSession> startSession(PlanDay day) async {
    final session = WorkoutSession(
      id: _newId(),
      planDayId: day.id,
      startedAt: _now(),
    );
    await _db.transaction(() async {
      await _db
          .into(_db.localSessions)
          .insert(
            LocalSessionsCompanion.insert(
              id: session.id,
              planDayId: Value(session.planDayId),
              startedAt: session.startedAt,
              status: 'in_progress',
            ),
          );
      await _enqueue(
        OutboxKind.insertSession,
        WorkoutJson.sessionToRow(session),
      );
    });
    return session;
  }

  @override
  Future<AssignedPlan?> completeSession(String sessionId) {
    return _db.transaction(() async {
      final row = await (_db.select(
        _db.localSessions,
      )..where((t) => t.id.equals(sessionId))).getSingleOrNull();
      final plan = await cachedPlan();
      if (row == null || row.status == 'completed') return plan;

      await (_db.update(
        _db.localSessions,
      )..where((t) => t.id.equals(sessionId))).write(
        LocalSessionsCompanion(
          status: const Value('completed'),
          endedAt: Value(_now()),
        ),
      );
      await _enqueue(OutboxKind.completeSession, {'session_id': sessionId});

      if (plan == null) return null;
      final day = plan.days.where((d) => d.id == row.planDayId).firstOrNull;
      if (day == null) return plan;
      final next = plan.copyWith(nextDayOrder: plan.dayAfter(day.dayOrder));
      await _cachePlan(next);
      return next;
    });
  }

  // ---------------------------------------------------------------- sets --

  @override
  Future<Map<String, List<LoggedSet>>> lastSets(
    Iterable<String> exerciseIds,
  ) async {
    final ids = exerciseIds.toSet();
    final open = await openSession();
    // Newest completed session per exercise. The open session is excluded so
    // "last time" doesn't change while you train.
    final query =
        _db.select(_db.localSets).join([
            innerJoin(
              _db.localSessions,
              _db.localSessions.id.equalsExp(_db.localSets.sessionId),
              useColumns: false,
            ),
          ])
          ..where(_db.localSets.exerciseId.isIn(ids))
          ..orderBy([OrderingTerm.desc(_db.localSets.loggedAt)]);
    if (open != null) {
      query.where(_db.localSets.sessionId.equals(open.id).not());
    }
    final rows = (await query.get()).map((r) => r.readTable(_db.localSets));

    // History pulled from the server has no local session row.
    final orphans =
        await (_db.select(_db.localSets)..where(
              (t) =>
                  t.exerciseId.isIn(ids) &
                  t.sessionId.isNotInQuery(
                    _db.selectOnly(_db.localSessions)
                      ..addColumns([_db.localSessions.id]),
                  ),
            ))
            .get();

    final all = [...rows, ...orphans]
      ..sort((a, b) => b.loggedAt.compareTo(a.loggedAt));
    final result = <String, List<LoggedSet>>{};
    final lastSessionOf = <String, String>{};
    for (final r in all) {
      final session = lastSessionOf.putIfAbsent(
        r.exerciseId,
        () => r.sessionId,
      );
      if (session != r.sessionId) continue;
      (result[r.exerciseId] ??= []).add(_set(r));
    }
    for (final sets in result.values) {
      sets.sort((a, b) => a.setNumber.compareTo(b.setNumber));
    }
    return result;
  }

  @override
  Future<List<LoggedSet>> setsOf(String sessionId) async {
    final rows =
        await (_db.select(_db.localSets)
              ..where((t) => t.sessionId.equals(sessionId))
              ..orderBy([(t) => OrderingTerm.asc(t.loggedAt)]))
            .get();
    return rows.map(_set).toList();
  }

  @override
  Future<LoggedSet> logSet({
    required String sessionId,
    required String exerciseId,
    required int setNumber,
    required double weightKg,
    required int reps,
  }) async {
    final set = LoggedSet(
      id: _newId(),
      sessionId: sessionId,
      exerciseId: exerciseId,
      setNumber: setNumber,
      weightKg: weightKg,
      reps: reps,
      loggedAt: _now(),
    );
    await _db.transaction(() async {
      await _db.into(_db.localSets).insert(_setCompanion(set));
      await _enqueue(OutboxKind.upsertSet, WorkoutJson.setToRow(set));
    });
    return set;
  }

  @override
  Future<void> updateSet(LoggedSet set) => _db.transaction(() async {
    await _db.into(_db.localSets).insertOnConflictUpdate(_setCompanion(set));
    await _enqueue(OutboxKind.upsertSet, WorkoutJson.setToRow(set));
  });

  @override
  Future<void> deleteSet(String setId) => _db.transaction(() async {
    await (_db.delete(_db.localSets)..where((t) => t.id.equals(setId))).go();
    await _enqueue(OutboxKind.deleteSet, {'id': setId});
  });

  // ---------------------------------------------------------------- sync --

  @override
  Stream<int> watchPendingCount() {
    final count = _db.outbox.seq.count();
    return (_db.selectOnly(
      _db.outbox,
    )..addColumns([count])).map((r) => r.read(count) ?? 0).watchSingle();
  }

  @override
  Future<Result<int>> sync() async {
    if (_syncing) return const Success(0);
    _syncing = true;
    var pushed = 0;
    try {
      if (!await _remote.ensureReady()) return const Success(0);
      final pending = await (_db.select(
        _db.outbox,
      )..orderBy([(t) => OrderingTerm.asc(t.seq)])).get();
      for (final item in pending) {
        try {
          await _push(item);
        } on Object catch (error, stackTrace) {
          final failure = AppFailure.from(error);
          if (failure.isRetryable) return Failed(failure);
          final attempts = item.attempts + 1;
          if (attempts < maxAttempts) {
            await (_db.update(_db.outbox)..where((t) => t.seq.equals(item.seq)))
                .write(OutboxCompanion(attempts: Value(attempts)));
            return Failed(failure);
          }
          // Give up on this write so the rest of the queue can sync.
          unawaited(Monitoring.captureException(error, stackTrace));
        }
        await (_db.delete(
          _db.outbox,
        )..where((t) => t.seq.equals(item.seq))).go();
        pushed++;
      }
      return Success(pushed);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _push(OutboxData item) async {
    final payload = jsonDecode(item.payload) as Map<String, dynamic>;
    switch (item.kind) {
      case OutboxKind.insertSession:
        await _remote.insertSession(payload);
      case OutboxKind.upsertSet:
        await _remote.upsertSet(payload);
      case OutboxKind.deleteSet:
        await _remote.deleteSet(payload['id'] as String);
      case OutboxKind.completeSession:
        await _remote.completeSession(payload['session_id'] as String);
      default:
        throw FormatException('Unknown outbox kind ${item.kind}');
    }
  }

  Future<void> _enqueue(String kind, Map<String, dynamic> payload) => _db
      .into(_db.outbox)
      .insert(
        OutboxCompanion.insert(
          kind: kind,
          payload: jsonEncode(payload),
          createdAt: _now(),
        ),
      );

  // ------------------------------------------------------------- mapping --

  static WorkoutSession _session(LocalSession row) => WorkoutSession(
    id: row.id,
    planDayId: row.planDayId,
    startedAt: row.startedAt,
    endedAt: row.endedAt,
    status: row.status == 'completed'
        ? SessionStatus.completed
        : SessionStatus.inProgress,
  );

  static LoggedSet _set(LocalSet row) => LoggedSet(
    id: row.id,
    sessionId: row.sessionId,
    exerciseId: row.exerciseId,
    setNumber: row.setNumber,
    weightKg: row.weightKg,
    reps: row.reps,
    loggedAt: row.loggedAt,
  );

  static LocalSetsCompanion _setCompanion(LoggedSet s) =>
      LocalSetsCompanion.insert(
        id: s.id,
        sessionId: s.sessionId,
        exerciseId: s.exerciseId,
        setNumber: s.setNumber,
        weightKg: s.weightKg,
        reps: s.reps,
        loggedAt: s.loggedAt,
      );
}
