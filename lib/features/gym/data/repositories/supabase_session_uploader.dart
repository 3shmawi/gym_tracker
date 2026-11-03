import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/repositories/session_outbox.dart';
import 'package:gym_tracker/features/gym/domain/repositories/solo_import_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Inserts finished gym workouts into `workout_sessions` (RLS "log own
/// sessions": the person, and a gym where their membership is active).
/// `on conflict (person_id, client_id) do nothing`, so a workout already
/// there is not stored twice and a retry after a lost answer is safe.
class SupabaseSessionUploader implements SessionUploader {
  new(this._client, {this.retries = 2, this.personId, this.insert});

  final SupabaseClient _client;
  final int retries;

  /// The person's id; the default reads `people` (RLS: own row).
  final Future<String> Function()? personId;

  /// Writes the rows; tests pass a recorder.
  final Future<void> Function(List<Map<String, Object?>> rows)? insert;

  String? _person;

  @override
  Future<Result<void>> upload(List<OutboxEntry> entries) => guard(() async {
    if (entries.isEmpty) return;
    if (entries.length > maxChunk) {
      throw const FormatException('chunk too large');
    }
    final person = _person ??= await (personId ?? _readPerson)();
    final rows = [
      for (final e in entries)
        {
          'client_id': e.clientId,
          'person_id': person,
          'gym_id': e.gymId,
          'membership_id': e.membershipId,
          'day_id': e.session.dayId,
          'finished_at': e.session.finishedAt.toUtc().toIso8601String(),
          'sets': [for (final s in e.session.sets) s.toJson()],
        },
    ];
    await (insert ?? _insert)(rows);
  }, retries: retries);

  Future<String> _readPerson() async {
    final row = await _client.from('people').select('id').single();
    return row['id']! as String;
  }

  Future<void> _insert(List<Map<String, Object?>> rows) => _client
      .from('workout_sessions')
      .upsert(rows, onConflict: 'person_id,client_id', ignoreDuplicates: true);
}
