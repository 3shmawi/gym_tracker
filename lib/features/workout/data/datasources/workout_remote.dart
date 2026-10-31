import 'package:gym_tracker/features/workout/data/models/workout_json.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Server side of the workout feature. Faked in tests.
abstract interface class WorkoutRemote {
  /// False when the backend isn't configured or nobody is signed in: writes
  /// stay queued on the device.
  bool get isReady;

  Future<AssignedPlan?> fetchActivePlan();

  /// Sets of the member's last session for every exercise.
  Future<List<LoggedSet>> fetchLastSets();

  /// Creates the session; does nothing if it already exists (safe retry).
  Future<void> insertSession(Map<String, dynamic> row);

  Future<void> upsertSet(Map<String, dynamic> row);

  Future<void> deleteSet(String id);

  /// Returns the next day order (null for a session outside a plan).
  Future<int?> completeSession(String sessionId);
}

class SupabaseWorkoutRemote implements WorkoutRemote {
  new(this._client);

  final SupabaseClient? _client;

  static const planSelect =
      'next_day_order, plans(id, name, plan_days(id, day_order, name_en, '
      'name_ar, plan_exercises(position, sets, target_reps, rest_seconds, '
      'weight_step_kg, superset_group, exercises(id, name_en, name_ar))))';

  SupabaseClient get _db => _client!;

  @override
  bool get isReady => _client?.auth.currentUser != null;

  @override
  Future<AssignedPlan?> fetchActivePlan() async {
    final row = await _db
        .from('plan_assignments')
        .select(planSelect)
        .eq('active', true)
        .maybeSingle();
    return row == null ? null : WorkoutJson.planFromAssignment(row);
  }

  @override
  Future<List<LoggedSet>> fetchLastSets() async {
    final rows = await _db
        .from('exercise_last_sets')
        .select(
          'id, session_id, exercise_id, set_number, weight_kg, reps, logged_at',
        );
    return rows.map(WorkoutJson.setFromRow).toList();
  }

  @override
  Future<void> insertSession(Map<String, dynamic> row) =>
      _db.from('sessions').upsert(row, ignoreDuplicates: true);

  @override
  Future<void> upsertSet(Map<String, dynamic> row) =>
      _db.from('set_logs').upsert(row);

  @override
  Future<void> deleteSet(String id) =>
      _db.from('set_logs').delete().eq('id', id);

  @override
  Future<int?> completeSession(String sessionId) async {
    final next = await _db.rpc<dynamic>(
      'complete_session',
      params: {'p_session_id': sessionId},
    );
    return next as int?;
  }
}
