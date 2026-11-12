import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/backup/data/restore_rows.dart';
import 'package:gym_tracker/features/backup/domain/entities/restore.dart';
import 'package:gym_tracker/features/backup/domain/repositories/backup_repositories.dart';
import 'package:gym_tracker/features/gym/data/repositories/supabase_session_uploader.dart';
import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// [BackupRemote] on Supabase (migration 0022): `ensure_person`, direct
/// upsert of solo rows (RLS "log own sessions", `on conflict (person_id,
/// client_id) do nothing`), `save_personal_plan`, `save_personal_state`.
class SupabaseBackupRemote implements BackupRemote {
  new(
    this._client, {
    this.retries = 2,
    this.readPerson,
    this.insert,
    this.call,
    this.readSessions,
    this.readOne,
    this.now = DateTime.now,
  });

  final SupabaseClient _client;
  final int retries;

  /// Tests pass these; the defaults talk to Supabase: the person's id
  /// (`people`,
  /// RLS: own row; null = none yet), the rows to upsert, and an RPC by name.
  final Future<String?> Function()? readPerson;
  final Future<void> Function(List<Map<String, Object?>> rows)? insert;
  final Future<Object?> Function(String name, Map<String, Object?>? params)?
  call;

  /// Tests pass these for the restore reads: a page of workout rows after a
  /// cursor, and the single row of a table (`personal_plans`,
  /// `personal_state`) or null.
  final Future<List<Map<String, Object?>>> Function(
    RestoreCursor? after,
    int limit,
  )?
  readSessions;
  final Future<Map<String, Object?>?> Function(String table)? readOne;
  final DateTime Function() now;

  String? _person;

  /// The upload cap of one request.
  static const maxChunk = 50;

  @override
  Future<Result<void>> ensurePerson() => guard(() async {
    if (_person != null) return;
    final known = await (readPerson ?? _readPerson)();
    if (known != null) {
      _person = known;
      return;
    }
    final id = await (call ?? _rpc)('ensure_person', null);
    _person = id is String ? id : null;
    if (_person == null) throw const FormatException('no person id');
  }, retries: retries);

  @override
  Future<Result<void>> uploadSessions(List<WorkoutSession> sessions) =>
      guard(() async {
        if (sessions.isEmpty) return;
        if (sessions.length > maxChunk) {
          throw const FormatException('chunk too large');
        }
        final person = _person;
        if (person == null) throw const FormatException('no person');
        await (insert ?? _insert)([
          for (final s in sessions)
            {
              'client_id': s.clientId,
              'person_id': person,
              'day_id': s.dayId,
              'finished_at': s.finishedAt.toUtc().toIso8601String(),
              'started_at': SupabaseSessionUploader.startOf(s),
              'sets': [for (final x in s.sets) x.toJson()],
            },
        ]);
      }, retries: retries);

  @override
  Future<Result<int>> savePlan(int baseVersion, WorkoutPlan plan) =>
      guard(() async {
        final answer = await (call ?? _rpc)('save_personal_plan', {
          'p_base_version': baseVersion,
          'p_body': plan.toJson(),
        });
        final version = answer is Map ? answer['version'] : null;
        if (version is! int || version < 1) {
          throw const FormatException('no plan version');
        }
        return version;
      }, retries: 0);

  @override
  Future<Result<void>> deleteBackup() =>
      guard(() => (call ?? _rpc)('delete_my_backup', null), retries: retries);

  @override
  Future<Result<void>> saveState(Level bestLevel, ChosenDay? chosenDay) =>
      guard(
        () => (call ?? _rpc)('save_personal_state', {
          'p_best_level': bestLevel.name,
          'p_chosen_day': chosenDay?.toJson(),
        }),
        retries: retries,
      );

  Future<String?> _readPerson() async {
    final row = await _client.from('people').select('id').maybeSingle();
    return row?['id'] as String?;
  }

  Future<void> _insert(List<Map<String, Object?>> rows) => _client
      .from('workout_sessions')
      .upsert(rows, onConflict: 'person_id,client_id', ignoreDuplicates: true);

  Future<Object?> _rpc(String name, Map<String, Object?>? params) =>
      _client.rpc<Object?>(name, params: params);

  /// At most this many workouts in one page.
  static const maxPage = 200;

  @override
  Future<Result<RestorePage>> fetchSessions({
    RestoreCursor? after,
    int limit = maxPage,
  }) => guard(() async {
    final size = limit.clamp(1, maxPage);
    final rows = await (readSessions ?? _readSessions)(after, size + 1);
    // One more than asked says there is a next page.
    final more = rows.length > size;
    final page = more ? rows.sublist(0, size) : rows;
    final sessions = <WorkoutSession>[];
    var skipped = 0;
    for (final row in page) {
      final session = RestoreRows.session(row, now());
      if (session == null) {
        skipped++;
      } else {
        sessions.add(session);
      }
    }
    RestoreCursor? next;
    if (more) {
      final last = page.last;
      final at = last['finished_at'];
      final id = last['id'];
      if (at is! String || id is! String || DateTime.tryParse(at) == null) {
        // A page we cannot continue after: stop here, the next run tries again.
        throw const FormatException('page without a position');
      }
      next = RestoreCursor(at, id);
    }
    return RestorePage(sessions: sessions, skipped: skipped, next: next);
  }, retries: retries);

  @override
  Future<Result<RemotePlan?>> fetchPlan() => guard(() async {
    final row = await (readOne ?? _readOne)('personal_plans');
    if (row == null) return null;
    final plan = RestoreRows.plan(row['body']);
    final version = row['version'];
    if (plan == null || version is! int || version < 1) {
      throw const FormatException('the account has a plan the app cannot read');
    }
    return RemotePlan(plan, version);
  }, retries: retries);

  @override
  Future<Result<RemoteState?>> fetchState() => guard(() async {
    final row = await (readOne ?? _readOne)('personal_state');
    if (row == null) return null;
    return RemoteState(
      Level.fromName(row['best_level']?.toString()),
      ChosenDay.fromJson(row['chosen_day']),
    );
  }, retries: retries);

  Future<List<Map<String, Object?>>> _readSessions(
    RestoreCursor? after,
    int limit,
  ) async {
    var query = _client
        .from('workout_sessions')
        .select(
          'id, gym_id, membership_id, day_id, finished_at, started_at, sets',
        );
    if (after != null) {
      // finished_at after the cursor, or the same time with a bigger id.
      query = query.or(
        'finished_at.gt.${after.finishedAt},'
        'and(finished_at.eq.${after.finishedAt},id.gt.${after.id})',
      );
    }
    final rows = await query.order('finished_at').order('id').limit(limit);
    return [for (final r in rows) Map<String, Object?>.from(r)];
  }

  Future<Map<String, Object?>?> _readOne(String table) async {
    final columns = table == 'personal_plans'
        ? 'body, version'
        : 'best_level, chosen_day';
    final row = await _client.from(table).select(columns).maybeSingle();
    return row == null ? null : Map<String, Object?>.from(row);
  }
}
