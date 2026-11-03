import 'dart:convert';

import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_plan.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_plan_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// `plans` (read, RLS: the active member and the gym's managers) and
/// `save_plan(p_membership_id, p_base_version, p_body)` (migration 0007).
class SupabaseGymPlanRepository implements GymPlanRepository {
  const new(this._client, {this.retries = 2, this.readRow, this.call});

  final SupabaseClient _client;
  final int retries;

  /// Reads the `plans` row (`body`, `version`, `updated_by`) or null; tests
  /// pass rows.
  final Future<Map<String, Object?>?> Function(String membershipId)? readRow;

  /// Calls `save_plan`; tests pass an answer.
  final Future<Object?> Function(Map<String, Object?> params)? call;

  @override
  Future<Result<GymPlan?>> fetch(String membershipId) => guard(() async {
    final row = await (readRow ?? _read)(membershipId);
    return row == null ? null : _parse(membershipId, row);
  }, retries: retries);

  @override
  Future<Result<GymPlan>> save(
    String membershipId,
    int baseVersion,
    WorkoutPlan plan,
  ) => guard(
    () async {
      final answer = await (call ?? _rpc)({
        'p_membership_id': membershipId,
        'p_base_version': baseVersion,
        'p_body': plan.toJson(),
      });
      if (answer is! Map) throw const FormatException('save_plan answer');
      final version = answer['version'];
      if (version is! int || version < 1) {
        throw const FormatException('save_plan version');
      }
      return GymPlan(
        membershipId: membershipId,
        plan: plan,
        version: version,
        updatedBy: answer['updated_by'] as String?,
      );
    },
    // Never retried: a second try after a lost answer would see its own
    // change as "plan_changed".
    retries: 0,
  );

  static GymPlan _parse(String membershipId, Map<String, Object?> row) {
    final body = row['body'];
    final version = row['version'];
    if (body is! Map || version is! int || version < 1) {
      throw const FormatException('plan row');
    }
    return GymPlan(
      membershipId: membershipId,
      plan: WorkoutPlan.fromJson(Map<String, Object?>.from(body)),
      version: version,
      updatedBy: row['updated_by'] as String?,
    );
  }

  /// Own rows only (RLS). Explicit columns: a new column never reaches the
  /// phone by accident.
  Future<Map<String, Object?>?> _read(String membershipId) async {
    final row = await _client
        .from('plans')
        .select('body, version, updated_by')
        .eq('membership_id', membershipId)
        .maybeSingle();
    return row == null ? null : Map<String, Object?>.from(row);
  }

  Future<Object?> _rpc(Map<String, Object?> params) =>
      _client.rpc<Object?>('save_plan', params: params);
}

/// The size a plan may have on the server (`plans.body`, 64 KB).
bool planFitsServer(WorkoutPlan plan) =>
    utf8.encode(jsonEncode(plan.toJson())).length <= 65536;
