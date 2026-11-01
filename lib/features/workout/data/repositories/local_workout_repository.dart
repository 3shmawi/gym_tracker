import 'dart:convert';

import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_draft.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [WorkoutRepository] on the phone (SharedPreferences, JSON). Works
/// offline; syncing to Supabase comes with accounts.
///
/// Corrupt data is reported as a failure (never a crash), so the screen can
/// show the error state.
class LocalWorkoutRepository implements WorkoutRepository {
  new(this._prefs);

  final SharedPreferences _prefs;

  static const planKey = 'workout.plan';
  static const historyKey = 'workout.history';
  static const chosenDayKey = 'workout.chosen_day';
  static const draftKey = 'workout.draft';

  /// Oldest sessions are dropped beyond this; suggestions only need the
  /// latest one per exercise.
  static const maxHistory = 200;

  @override
  Future<Result<WorkoutPlan?>> loadPlan() => guard(() async {
    final raw = _prefs.getString(planKey);
    if (raw == null) return null;
    return _parse<WorkoutPlan>(() => WorkoutPlan.fromJson(_decodeMap(raw)));
  }, retries: 0);

  @override
  Future<Result<void>> savePlan(WorkoutPlan plan) => guard(
    () => _prefs.setString(planKey, jsonEncode(plan.toJson())),
    retries: 0,
  );

  @override
  Future<Result<List<WorkoutSession>>> loadHistory() =>
      guard(() async => _readHistory(), retries: 0);

  @override
  Future<Result<void>> saveSession(WorkoutSession session) => guard(() async {
    final history = [..._readHistory(), session];
    final kept = history.length > maxHistory
        ? history.sublist(history.length - maxHistory)
        : history;
    await _prefs.setString(
      historyKey,
      jsonEncode([for (final s in kept) s.toJson()]),
    );
    await _prefs.remove(chosenDayKey);
  }, retries: 0);

  @override
  Future<Result<WorkoutDraft?>> loadDraft() => guard(() async {
    final raw = _prefs.getString(draftKey);
    if (raw == null) return null;
    return _parse<WorkoutDraft>(() => WorkoutDraft.fromJson(_decodeMap(raw)));
  }, retries: 0);

  @override
  Future<Result<void>> saveDraft(WorkoutDraft? draft) => guard(
    () => draft == null
        ? _prefs.remove(draftKey)
        : _prefs.setString(draftKey, jsonEncode(draft.toJson())),
    retries: 0,
  );

  @override
  Future<Result<int?>> loadChosenDay() =>
      guard(() async => _prefs.getInt(chosenDayKey), retries: 0);

  @override
  Future<Result<void>> saveChosenDay(int? dayIndex) => guard(
    () => dayIndex == null
        ? _prefs.remove(chosenDayKey)
        : _prefs.setInt(chosenDayKey, dayIndex),
    retries: 0,
  );

  List<WorkoutSession> _readHistory() {
    final raw = _prefs.getString(historyKey);
    if (raw == null) return [];
    final list = jsonDecode(raw);
    if (list is! List<Object?>) {
      throw const FormatException('workout history is not a list');
    }
    return _parse(
      () => [for (final item in list) WorkoutSession.fromJson(_asMap(item))],
    );
  }

  /// Wrong types in stored JSON (a hand-edited or old format) become a
  /// [FormatException], i.e. a validation failure, not an unknown crash.
  static T _parse<T>(T Function() parse) {
    try {
      return parse();
      // A cast failure in our own parser is data, not a bug: report it as one.
      // ignore: avoid_catching_errors
    } on TypeError catch (error) {
      throw FormatException('stored workout data is invalid: $error');
    }
  }

  static Map<String, Object?> _decodeMap(String raw) => _asMap(jsonDecode(raw));

  static Map<String, Object?> _asMap(Object? value) {
    if (value is! Map<String, Object?>) {
      throw const FormatException('expected a JSON object');
    }
    return value;
  }
}
