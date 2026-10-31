import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'workout_database.g.dart';

/// Small key → JSON store, used for the cached plan.
class CacheEntries extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

class LocalSessions extends Table {
  TextColumn get id => text()();
  TextColumn get planDayId => text().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();

  /// `in_progress` or `completed`.
  TextColumn get status => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class LocalSets extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text()();
  TextColumn get exerciseId => text()();
  IntColumn get setNumber => integer()();
  RealColumn get weightKg => real()();
  IntColumn get reps => integer()();
  DateTimeColumn get loggedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Writes waiting to reach Supabase, replayed in [seq] order.
class Outbox extends Table {
  IntColumn get seq => integer().autoIncrement()();

  /// See `OutboxKind`.
  TextColumn get kind => text()();
  TextColumn get payload => text()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
}

@DriftDatabase(tables: [CacheEntries, LocalSessions, LocalSets, Outbox])
class WorkoutDatabase extends _$WorkoutDatabase {
  new([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'workout'));

  @override
  int get schemaVersion => 1;
}
