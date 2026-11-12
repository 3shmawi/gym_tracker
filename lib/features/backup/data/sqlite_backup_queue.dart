import 'package:gym_tracker/features/backup/domain/repositories/backup_repositories.dart';
import 'package:gym_tracker/features/workout/data/local/workout_database.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:sqflite/sqflite.dart';

/// [BackupQueue] on the phone's database: the rows of `sessions` whose
/// `synced_at` is empty. Only solo workouts (`membership_id` null); a gym
/// workout goes up through the gym's outbox.
class SqliteBackupQueue implements BackupQueue {
  new(this._db, {this.now = DateTime.now});

  final Database _db;
  final DateTime Function() now;

  static const _waiting =
      'synced_at IS NULL AND sync_problem IS NULL AND membership_id IS NULL';

  @override
  Future<List<WorkoutSession>> pending(int limit) async {
    final rows = await _db.query(
      'sessions',
      where: _waiting,
      orderBy: 'finished_at, rowid',
      limit: limit,
    );
    final sessions = <WorkoutSession>[];
    for (final row in rows) {
      try {
        sessions.add(SqliteSessionStore.fromRow(row));
      } on Object {
        // Unreadable: it will be set aside the next time history is read.
        await markProblem(row['client_id']! as String, 'unreadable');
      }
    }
    return sessions;
  }

  @override
  Future<void> markSynced(Iterable<String> clientIds) async {
    final ids = clientIds.toList();
    if (ids.isEmpty) return;
    await _db.update(
      'sessions',
      {'synced_at': now().millisecondsSinceEpoch},
      where: 'client_id IN (${List.filled(ids.length, '?').join(',')})',
      whereArgs: ids,
    );
  }

  @override
  Future<void> markProblem(String clientId, String reason) => _db.update(
    'sessions',
    {'sync_problem': reason},
    where: 'client_id = ?',
    whereArgs: [clientId],
  );

  @override
  Future<void> resetAll() => _db.update('sessions', {
    'synced_at': null,
    'sync_problem': null,
  }, where: 'membership_id IS NULL');

  @override
  Future<int> pendingCount() => _count(_waiting);

  @override
  Future<int> problemCount() =>
      _count('sync_problem IS NOT NULL AND membership_id IS NULL');

  Future<int> _count(String where) async =>
      Sqflite.firstIntValue(
        await _db.rawQuery('SELECT count(*) FROM sessions WHERE $where'),
      ) ??
      0;
}
