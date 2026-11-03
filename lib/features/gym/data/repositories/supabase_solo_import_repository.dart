import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/solo_import.dart';
import 'package:gym_tracker/features/gym/domain/repositories/solo_import_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `import_solo_data(p_sessions, p_plan)` (migration 0009): at most 50
/// workouts a call, all-or-nothing, idempotent. Errors map through
/// `AppFailure.from` (`22023` → validation, `42501` → unauthorized).
class SupabaseSoloImportRepository implements SoloImportRepository {
  const new(this._client, {this.retries = 2, this.call});

  final SupabaseClient _client;
  final int retries;

  /// Makes the RPC; the default asks Supabase. Tests pass an answer.
  final Future<Object?> Function(String name, Map<String, Object?> params)?
  call;

  @override
  Future<Result<ImportAck>> importChunk(
    List<ImportSession> sessions, {
    WorkoutPlan? plan,
  }) => guard(() async {
    if (sessions.length > maxChunk) {
      throw const FormatException('chunk too large');
    }
    final params = <String, Object?>{
      'p_sessions': [for (final s in sessions) s.toJson()],
      'p_plan': plan?.toJson(),
    };
    final answer = await (call ?? _rpc)('import_solo_data', params);
    return ImportAck.fromJson(answer);
  }, retries: retries);

  Future<Object?> _rpc(String name, Map<String, Object?> params) =>
      _client.rpc<Object?>(name, params: params);
}
