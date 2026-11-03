import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_media.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_media_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `gym_exercise_images` (migration 0015; RLS: the gym's active members).
class SupabaseGymMediaRepository implements GymMediaRepository {
  const new(this._client, {this.retries = 2, this.readRows});

  final SupabaseClient _client;
  final int retries;

  /// Reads the rows; tests pass rows.
  final Future<List<Object?>> Function(String gymId)? readRows;

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  @override
  Future<Result<GymMedia>> fetch(String gymId) => guard(() async {
    if (!_uuid.hasMatch(gymId)) throw const FormatException('gym id');
    final rows = await (readRows ?? _read)(gymId);
    // A row outside the rules is dropped, never shown.
    return GymMedia.fromPictures(
      rows.map(GymExercisePicture.tryParse).nonNulls,
    );
  }, retries: retries);

  /// Explicit columns (a new column never reaches the phone by accident) and
  /// the database's own limit as the page size.
  Future<List<Object?>> _read(String gymId) => _client
      .from('gym_exercise_images')
      .select('exercise_id, public_id, position')
      .eq('gym_id', gymId)
      .order('exercise_id')
      .order('position')
      .limit(GymMedia.maxRows);
}
