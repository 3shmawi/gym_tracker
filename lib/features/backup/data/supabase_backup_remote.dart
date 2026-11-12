import 'package:gym_tracker/core/network/result.dart';
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
}
