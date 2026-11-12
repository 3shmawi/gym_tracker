import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:gym_tracker/features/workout/data/local/stored_json.dart';
import 'package:gym_tracker/features/workout/data/local/workout_stores.dart';
import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/repositories/restore_sink.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// What happened while the database was opened (for monitoring and
/// analytics; never contains a workout).
class DatabaseOpenReport {
  const new({
    required this.migrated,
    required this.sessionsMoved,
    required this.quarantined,
    required this.elapsed,
    required this.repaired,
  });

  /// Workouts or values were moved from the old preferences on this start.
  final bool migrated;
  final int sessionsMoved;

  /// Items that could not be read and were set aside.
  final int quarantined;
  final Duration elapsed;

  /// The database file was unreadable and a new one was made.
  final bool repaired;
}

/// A step of the move that failed; [reason] is one word for analytics.
class DatabaseMoveException implements Exception {
  const new(this.reason, this.message);

  final String reason;
  final String message;

  @override
  String toString() => 'DatabaseMoveException($reason): $message';
}

/// The phone's database for the workout repository (schema version 1):
/// `sessions` (one row per finished workout, keyed by its content hash),
/// `kv` (plan, draft, chosen day, level and markers) and `quarantine` (what
/// could not be read). Design: docs/designs/never_lose_history.md §1.
class WorkoutDatabase {
  new _(this.database, this.kv, this.sessions, this.report);

  final Database database;
  final SqliteWorkoutKv kv;
  final SqliteSessionStore sessions;
  final DatabaseOpenReport report;

  static const version = 1;
  static const fileName = 'azm.db';

  /// Marker of the move from preferences, and the fingerprints of what was
  /// moved (one per old key), so a start can tell whether the old keys
  /// changed since (a start that used the preferences, or an older release).
  static const String migratedMarker = 'meta.migrated_v1';
  static String _sourceKey(String key) => 'meta.src.$key';

  /// The old preferences keys that are moved, and where the new copy goes.
  static const List<String> _oldKeys = [
    LocalKeys.history,
    LocalKeys.plan,
    LocalKeys.draft,
    LocalKeys.chosenDay,
    LocalKeys.legacyChosenDay,
    LocalKeys.level,
  ];

  /// Opens (and if needed creates, repairs and fills) the database at
  /// [path]. Throws when it cannot be done; the caller then keeps using the
  /// preferences. The old preference keys are never changed.
  static Future<WorkoutDatabase> open({
    required DatabaseFactory factory,
    required String path,
    required SharedPreferences prefs,
    DateTime Function() now = DateTime.now,
  }) async {
    final started = Stopwatch()..start();
    var repaired = false;
    Database db;
    try {
      db = await _open(factory, path);
    } on DatabaseException {
      // A file that cannot be opened (corrupt): put it aside, start a new
      // one; the move below fills it from the old keys.
      if (path == inMemoryDatabasePath) rethrow;
      await _setAside(factory, path, now());
      repaired = true;
      db = await _open(factory, path);
    }
    try {
      final kv = await SqliteWorkoutKv.load(db);
      final result = await _move(db, kv, prefs);
      final sessions = await SqliteSessionStore.create(db);
      started.stop();
      return WorkoutDatabase._(
        db,
        kv,
        sessions,
        DatabaseOpenReport(
          migrated: result.moved,
          sessionsMoved: result.sessions,
          quarantined: result.quarantined,
          elapsed: started.elapsed,
          repaired: repaired,
        ),
      );
    } on Object {
      await db.close();
      rethrow;
    }
  }

  static Future<Database> _open(DatabaseFactory factory, String path) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(version: version, onCreate: _create),
    );
    // Opening a damaged file can succeed; reading it is what fails.
    try {
      await db.rawQuery('SELECT count(*) FROM sqlite_master');
    } on Object {
      await db.close();
      rethrow;
    }
    return db;
  }

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
CREATE TABLE sessions(
  client_id TEXT PRIMARY KEY,
  day_id TEXT NOT NULL,
  finished_at INTEGER NOT NULL,
  started_at INTEGER,
  membership_id TEXT,
  sets TEXT NOT NULL,
  synced_at INTEGER,
  sync_problem TEXT
)''');
    await db.execute('CREATE INDEX sessions_finished ON sessions(finished_at)');
    await db.execute(
      'CREATE TABLE kv(key TEXT PRIMARY KEY, value TEXT NOT NULL)',
    );
    await db.execute('''
CREATE TABLE quarantine(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  kind TEXT NOT NULL,
  raw TEXT NOT NULL,
  at INTEGER NOT NULL
)''');
  }

  static Future<void> _setAside(
    DatabaseFactory factory,
    String path,
    DateTime now,
  ) async {
    final stamp = now.millisecondsSinceEpoch;
    for (final suffix in ['', '-journal', '-wal', '-shm']) {
      final file = File('$path$suffix');
      if (file.existsSync()) await file.rename('$path.corrupt-$stamp$suffix');
    }
  }

  /// Moves what the preferences hold that the database does not have yet.
  /// One transaction: it either completes (and the marker is written) or
  /// changes nothing.
  static Future<({bool moved, int sessions, int quarantined})> _move(
    Database db,
    SqliteWorkoutKv kv,
    SharedPreferences prefs,
  ) async {
    final first = kv.get(migratedMarker) == null;
    // Which old keys have a value that is not what was moved last time.
    final changed = <String, String>{};
    for (final key in _oldKeys) {
      final value = prefs.get(key);
      if (value == null) continue;
      final print = _fingerprint(value);
      if (kv.get(_sourceKey(key)) != print) changed[key] = print;
    }
    if (!first && changed.isEmpty) {
      return (moved: false, sessions: 0, quarantined: 0);
    }

    final pending = <String, String>{};
    var quarantined = 0;
    var sessionCount = 0;
    final setAside = <(String, String)>[];
    final parsed = <WorkoutSession>[];

    final historyRaw = changed.containsKey(LocalKeys.history)
        ? prefs.getString(LocalKeys.history)
        : null;
    if (historyRaw != null) {
      try {
        final list = jsonDecode(historyRaw);
        if (list is! List<Object?>) {
          throw const FormatException('workout history is not a list');
        }
        for (final item in list) {
          try {
            parsed.add(
              parseStored(() => WorkoutSession.fromJson(asStoredMap(item))),
            );
          } on Object {
            setAside.add(('session', jsonEncode(item)));
          }
        }
      } on Object {
        // The whole text is unreadable: keep it, start with no history.
        setAside.add(('history', historyRaw));
      }
    }
    quarantined = setAside.length;

    // The small values are copied as the raw strings the old keys hold.
    for (final key in [
      LocalKeys.plan,
      LocalKeys.draft,
      LocalKeys.chosenDay,
      LocalKeys.level,
    ]) {
      final value = prefs.get(key);
      if (changed.containsKey(key) && value is String) pending[key] = value;
    }
    // Before days had ids the chosen day was an int: carry it over as today's
    // format, unless the newer key is there.
    final legacy = prefs.get(LocalKeys.legacyChosenDay);
    if (changed.containsKey(LocalKeys.legacyChosenDay) &&
        legacy is int &&
        legacy >= 0 &&
        !pending.containsKey(LocalKeys.chosenDay) &&
        kv.get(LocalKeys.chosenDay) == null) {
      pending[LocalKeys.chosenDay] = jsonEncode(
        ChosenDay(legacyDayId(legacy)).toJson(),
      );
    }

    await db.transaction((txn) async {
      final existing = {
        for (final row in await txn.rawQuery('SELECT client_id FROM sessions'))
          row['client_id']! as String,
      };
      final distinct = {for (final s in parsed) s.clientId};
      final batch = txn.batch();
      for (final s in parsed) {
        batch.insert(
          'sessions',
          SqliteSessionStore.toRow(s),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await batch.commit(noResult: true);
      final count = Sqflite.firstIntValue(
        await txn.rawQuery('SELECT count(*) FROM sessions'),
      );
      final expected = existing.length + distinct.difference(existing).length;
      if (count != expected) {
        throw DatabaseMoveException(
          'verify',
          'rows $count, expected $expected',
        );
      }
      sessionCount = distinct.difference(existing).length;

      final at = DateTime.now().millisecondsSinceEpoch;
      for (final (kind, raw) in setAside) {
        await txn.insert('quarantine', {'kind': kind, 'raw': raw, 'at': at});
      }
      for (final entry in pending.entries) {
        await txn.insert('kv', {
          'key': entry.key,
          'value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final entry in changed.entries) {
        await txn.insert('kv', {
          'key': _sourceKey(entry.key),
          'value': entry.value,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.insert('kv', {
        'key': migratedMarker,
        'value': at.toString(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
    await kv.reload();
    return (moved: true, sessions: sessionCount, quarantined: quarantined);
  }

  static String _fingerprint(Object value) =>
      sha256.convert(utf8.encode(value.toString())).toString();

  /// Closes the database (tests; the app keeps it open for its lifetime).
  Future<void> close() => database.close();
}

/// The preferences keys of the workout repository.
abstract final class LocalKeys {
  static const history = 'workout.history';
  static const plan = 'workout.plan';
  static const draft = 'workout.draft';
  static const chosenDay = 'workout.next_day';
  static const legacyChosenDay = 'workout.chosen_day';
  static const level = 'workout.level';
}

/// [WorkoutKv] on the `kv` table, read from memory.
class SqliteWorkoutKv implements WorkoutKv {
  new _(this._db, this._cache);

  final Database _db;
  Map<String, String> _cache;

  static Future<SqliteWorkoutKv> load(Database db) async =>
      SqliteWorkoutKv._(db, await _read(db));

  static Future<Map<String, String>> _read(DatabaseExecutor db) async => {
    for (final row in await db.query('kv'))
      row['key']! as String: row['value']! as String,
  };

  /// Reads the table again (after the move wrote to it).
  Future<void> reload() async => _cache = await _read(_db);

  @override
  Object? get(String key) => _cache[key];

  @override
  Future<void> set(String key, String value) async {
    await _db.insert('kv', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    _cache = {..._cache, key: value};
  }

  @override
  Future<void> remove(String key) async {
    await _db.delete('kv', where: 'key = ?', whereArgs: [key]);
    _cache = {..._cache}..remove(key);
  }
}

/// [SessionStore] on the `sessions` table. No cap on history (a sanity limit
/// of [maxRows] stops a runaway bug); the parsed list is kept in memory and
/// dropped on a write.
class SqliteSessionStore implements SessionStore, RestoreSink {
  new _(this._db, this._rows);

  final Database _db;
  int _rows;
  List<WorkoutSession>? _cache;

  static const maxRows = 100000;

  static Future<SqliteSessionStore> create(Database db) async {
    final rows =
        Sqflite.firstIntValue(
          await db.rawQuery('SELECT count(*) FROM sessions'),
        ) ??
        0;
    return SqliteSessionStore._(db, rows);
  }

  static Map<String, Object?> toRow(WorkoutSession s) => {
    'client_id': s.clientId,
    'day_id': s.dayId,
    'finished_at': s.finishedAt.toUtc().microsecondsSinceEpoch,
    'started_at': s.startedAt?.toUtc().microsecondsSinceEpoch,
    'membership_id': s.membershipId,
    'sets': jsonEncode([for (final x in s.sets) x.toJson()]),
  };

  @override
  Future<List<WorkoutSession>> readAll() async {
    final cached = _cache;
    if (cached != null) return cached;
    final rows = await _db.query('sessions', orderBy: 'finished_at, rowid');
    final sessions = <WorkoutSession>[];
    for (final row in rows) {
      try {
        sessions.add(fromRow(row));
      } on Object {
        // A row we cannot read is set aside, not an error screen for ever.
        await _db.insert('quarantine', {
          'kind': 'row',
          'raw': jsonEncode(row),
          'at': DateTime.now().millisecondsSinceEpoch,
        });
        await _db.delete(
          'sessions',
          where: 'client_id = ?',
          whereArgs: [row['client_id']],
        );
        _rows--;
      }
    }
    return _cache = List.unmodifiable(sessions);
  }

  /// A stored row as a workout (throws when the row cannot be read).
  static WorkoutSession fromRow(Map<String, Object?> row) {
    final sets = jsonDecode(row['sets']! as String)! as List<Object?>;
    return WorkoutSession(
      dayId: row['day_id']! as String,
      finishedAt: DateTime.fromMicrosecondsSinceEpoch(
        row['finished_at']! as int,
        isUtc: true,
      ),
      startedAt: switch (row['started_at']) {
        final int us => DateTime.fromMicrosecondsSinceEpoch(us, isUtc: true),
        _ => null,
      },
      membershipId: row['membership_id'] as String?,
      sets: [for (final s in sets) LoggedSet.fromJson(asStoredMap(s))],
    );
  }

  @override
  Future<void> add(WorkoutSession session) async {
    if (_rows >= maxRows) {
      throw StateError('workout history is over $maxRows workouts');
    }
    final id = await _db.insert(
      'sessions',
      toRow(session),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (id != 0) _rows++;
    _cache = null;
  }

  /// Workouts of the account, taken onto this phone: already backed up
  /// (`synced_at` set), never twice (the key is the content), in one
  /// transaction. Returns how many were new.
  @override
  Future<int> addBackedUp(List<WorkoutSession> sessions) async {
    if (sessions.isEmpty) return 0;
    if (_rows + sessions.length > maxRows) {
      throw StateError('workout history is over $maxRows workouts');
    }
    final at = DateTime.now().millisecondsSinceEpoch;
    var added = 0;
    await _db.transaction((txn) async {
      for (final s in sessions) {
        final id = await txn.insert('sessions', {
          ...toRow(s),
          'synced_at': at,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (id != 0) added++;
      }
    });
    _rows += added;
    _cache = null;
    return added;
  }

  @override
  Future<int> count() async => _rows;

  @override
  Future<void> clear() async {
    await _db.delete('sessions');
    _rows = 0;
    _cache = null;
  }
}
