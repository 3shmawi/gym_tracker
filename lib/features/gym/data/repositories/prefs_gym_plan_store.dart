import 'dart:convert';

import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_plan.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_plan_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/session_outbox.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Each gym plan, for offline use, in shared preferences (not secret:
/// the plan the captain made for this person).
class PrefsGymPlanStore implements GymPlanStore {
  const new(this._prefs);

  final SharedPreferences _prefs;

  static String key(String membershipId) => 'gym.plan.$membershipId';

  static bool _safe(String id) => RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id);

  @override
  Future<Result<StoredGymPlan?>> load(String membershipId) => guard(() async {
    if (!_safe(membershipId)) return null;
    final raw = _prefs.getString(key(membershipId));
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, Object?>;
      final pending = map['pending'];
      return StoredGymPlan(
        plan: WorkoutPlan.fromJson(map['plan']! as Map<String, Object?>),
        version: map['version']! as int,
        seenVersion: (map['seen'] as int?) ?? 0,
        pending: pending is Map<String, Object?>
            ? GymPlan(
                membershipId: membershipId,
                plan: WorkoutPlan.fromJson(
                  pending['plan']! as Map<String, Object?>,
                ),
                version: pending['version']! as int,
                updatedBy: pending['updated_by'] as String?,
              )
            : null,
      );
      // A cast failure in our own parser is data, not a bug: no copy.
      // ignore: avoid_catching_errors
    } on TypeError {
      return null;
    } on FormatException {
      return null;
    }
  }, retries: 0);

  @override
  Future<Result<void>> save(String membershipId, StoredGymPlan stored) =>
      guard(() async {
        if (!_safe(membershipId)) throw const FormatException('membership id');
        final pending = stored.pending;
        await _prefs.setString(
          key(membershipId),
          jsonEncode({
            'plan': stored.plan.toJson(),
            'version': stored.version,
            'seen': stored.seenVersion,
            if (pending != null)
              'pending': {
                'plan': pending.plan.toJson(),
                'version': pending.version,
                'updated_by': pending.updatedBy,
              },
          }),
        );
      }, retries: 0);

  @override
  Future<Result<void>> clear(String membershipId) => guard(() async {
    await _prefs.remove(key(membershipId));
  }, retries: 0);
}

/// The finished gym workouts waiting for the server, in shared preferences.
class PrefsSessionOutbox implements SessionOutbox {
  const new(this._prefs);

  final SharedPreferences _prefs;

  static const storageKey = 'gym.session_outbox';

  /// More than a phone could ever hold offline; a corrupt or hostile value
  /// cannot grow the queue.
  static const maxEntries = 1000;

  List<OutboxEntry> _read() {
    final raw = _prefs.getString(storageKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw);
      if (list is! List<Object?> || list.length > maxEntries) return [];
      return [
        for (final item in list)
          OutboxEntry.fromJson(item! as Map<String, Object?>),
      ];
      // A cast failure in our own parser is data, not a bug: empty queue.
      // ignore: avoid_catching_errors
    } on TypeError {
      return [];
    } on FormatException {
      return [];
    }
  }

  Future<void> _write(List<OutboxEntry> entries) => _prefs.setString(
    storageKey,
    jsonEncode([for (final e in entries) e.toJson()]),
  );

  @override
  Future<Result<List<OutboxEntry>>> load() =>
      guard(() async => _read(), retries: 0);

  @override
  Future<Result<void>> add(OutboxEntry entry) => guard(() async {
    final all = _read();
    if (all.any((e) => e.clientId == entry.clientId)) return;
    if (all.length >= maxEntries) {
      throw const FormatException('outbox full');
    }
    await _write([...all, entry]);
  }, retries: 0);

  @override
  Future<Result<void>> remove(Set<String> clientIds) => guard(() async {
    final all = _read();
    await _write([
      for (final e in all)
        if (!clientIds.contains(e.clientId)) e,
    ]);
  }, retries: 0);
}
