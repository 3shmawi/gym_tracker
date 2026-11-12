import 'package:gym_tracker/features/workout/data/local/workout_database.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

/// The repository for this start, and the database under it (null when the
/// preferences are used).
class WorkoutStorage {
  const new(this.repository, this.database);

  final WorkoutRepository repository;
  final WorkoutDatabase? database;
}

/// What [openWorkoutRepository] tells the app, without a workout in it.
typedef DatabaseEvent = void Function(String name, Map<String, Object> data);

/// The workout repository for this start: on the phone's database when it
/// opens (the first start moves the old preferences in, see
/// [WorkoutDatabase]); otherwise on the preferences as before, with the
/// error reported and the database tried again on the next start. Never
/// throws: no error screen because of storage.
Future<WorkoutStorage> openWorkoutRepository(
  SharedPreferences prefs, {
  required DatabaseEvent onEvent,
  required void Function(Object error, StackTrace stack) onError,
  DatabaseFactory? factory,
  String? path,
}) async {
  try {
    final db = await WorkoutDatabase.open(
      factory: factory ?? databaseFactory,
      path: path ?? '${await getDatabasesPath()}/${WorkoutDatabase.fileName}',
      prefs: prefs,
    );
    final report = db.report;
    if (report.migrated) {
      onEvent('local_db_migrated', {
        'sessions': sessionsBucket(report.sessionsMoved),
        'ms': millisBucket(report.elapsed),
      });
    }
    if (report.repaired) {
      onEvent('local_db_migration_failed', {'reason': 'repaired'});
    }
    return WorkoutStorage(
      LocalWorkoutRepository.stores(db.kv, db.sessions),
      db,
    );
  } on DatabaseMoveException catch (error, stack) {
    onEvent('local_db_migration_failed', {'reason': error.reason});
    onError(error, stack);
  } on Object catch (error, stack) {
    onEvent('local_db_migration_failed', {'reason': 'open'});
    onError(error, stack);
  }
  return WorkoutStorage(LocalWorkoutRepository(prefs), null);
}

/// Analytics buckets (never an exact count).
String sessionsBucket(int n) => switch (n) {
  0 => '0',
  <= 50 => '1-50',
  <= 200 => '51-200',
  _ => '200+',
};

String millisBucket(Duration d) => switch (d.inMilliseconds) {
  < 50 => '<50',
  < 250 => '<250',
  < 1000 => '<1000',
  _ => '1000+',
};
