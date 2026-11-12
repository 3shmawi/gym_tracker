import 'dart:convert';

import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/data/local/stored_json.dart';
import 'package:gym_tracker/features/workout/data/local/workout_stores.dart';
import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_draft.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/usecases/plan_rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [WorkoutRepository] on the phone. Works offline. The small values live in
/// a [WorkoutKv] and the finished workouts in a [SessionStore]: both on
/// SharedPreferences (the original storage, and the fallback) or both in the
/// phone's database (`WorkoutDatabase`).
///
/// Corrupt data is reported as a failure (never a crash), so the screen can
/// show the error state.
class LocalWorkoutRepository implements WorkoutRepository {
  /// On SharedPreferences, as the app always did.
  new(SharedPreferences prefs)
    : _kv = PrefsWorkoutKv(prefs),
      _sessions = PrefsSessionStore(prefs);

  /// On the given stores (the phone's database).
  new stores(this._kv, this._sessions);

  final WorkoutKv _kv;
  final SessionStore _sessions;

  static const planKey = 'workout.plan';
  static const String historyKey = PrefsSessionStore.historyKey;
  static const chosenDayKey = 'workout.next_day';

  /// Before days had ids the chosen day was its 0-based position (int).
  /// Read once as `day-<n>` (see `legacyDayId`), removed on the next save.
  static const legacyChosenDayKey = 'workout.chosen_day';
  static const draftKey = 'workout.draft';
  static const levelKey = 'workout.level';

  /// Kept for the preferences store.
  static const int maxHistory = PrefsSessionStore.maxHistory;

  @override
  Future<Result<WorkoutPlan?>> loadPlan() => guard(() async {
    final raw = _stringOf(planKey);
    if (raw == null) return null;
    final plan = _parse<WorkoutPlan>(
      () => WorkoutPlan.fromJson(_decodeMap(raw)),
    );
    // Plans started from the old template had days 4 and 5 as copies of
    // days 1 and 2: give them the real days, unless a workout of one of them
    // is in progress (its logged sets point at the old exercises).
    final upgraded = PlanTemplates.upgrade(plan);
    if (identical(upgraded, plan)) return plan;
    final draftDay = _draftDayId();
    if (draftDay == 'day-4' || draftDay == 'day-5') return plan;
    await _kv.set(planKey, jsonEncode(upgraded.toJson()));
    return upgraded;
  }, retries: 0);

  String? _draftDayId() {
    final raw = _stringOf(draftKey);
    if (raw == null) return null;
    try {
      return WorkoutDraft.fromJson(_decodeMap(raw)).dayId;
    } on Object {
      return null;
    }
  }

  /// Refuses (`ValidationFailure`) a plan outside `PlanLimits`: no days,
  /// empty or long names, targets out of range, repeated ids. Names are
  /// stored as JSON text, never interpreted.
  @override
  Future<Result<void>> savePlan(WorkoutPlan plan) => guard(() async {
    final problem = validatePlan(plan);
    if (problem != null) throw FormatException('invalid plan: $problem');
    await _kv.set(planKey, jsonEncode(plan.toJson()));
  }, retries: 0);

  @override
  Future<Result<List<WorkoutSession>>> loadHistory() =>
      guard(_sessions.readAll, retries: 0);

  @override
  Future<Result<void>> saveSession(WorkoutSession session) => guard(() async {
    await _sessions.add(session);
    await _kv.remove(chosenDayKey);
    await _kv.remove(legacyChosenDayKey);
  }, retries: 0);

  @override
  Future<Result<WorkoutDraft?>> loadDraft() => guard(() async {
    final raw = _stringOf(draftKey);
    if (raw == null) return null;
    return _parse<WorkoutDraft>(() => WorkoutDraft.fromJson(_decodeMap(raw)));
  }, retries: 0);

  @override
  Future<Result<void>> saveDraft(WorkoutDraft? draft) => guard(
    () => draft == null
        ? _kv.remove(draftKey)
        : _kv.set(draftKey, jsonEncode(draft.toJson())),
    retries: 0,
  );

  /// A stored value of the wrong shape reads as no choice (the plan then
  /// follows the history) rather than an error screen.
  @override
  Future<Result<ChosenDay?>> loadChosenDay() => guard(() async {
    final raw = _kv.get(chosenDayKey);
    if (raw is String) {
      try {
        return ChosenDay.fromJson(jsonDecode(raw));
      } on FormatException {
        return null;
      }
    }
    final legacy = _kv.get(legacyChosenDayKey);
    return legacy is int && legacy >= 0 ? ChosenDay(legacyDayId(legacy)) : null;
  }, retries: 0);

  @override
  Future<Result<void>> saveChosenDay(ChosenDay? day) => guard(() async {
    await _kv.remove(legacyChosenDayKey);
    if (day == null) {
      await _kv.remove(chosenDayKey);
    } else {
      await _kv.set(chosenDayKey, jsonEncode(day.toJson()));
    }
  }, retries: 0);

  @override
  Future<Result<Level>> loadBestLevel() => guard(
    // Anything unexpected (another type, an unknown name) is a beginner.
    () async => Level.fromName(_kv.get(levelKey)?.toString()),
    retries: 0,
  );

  @override
  Future<Result<void>> saveBestLevel(Level level) =>
      guard(() => _kv.set(levelKey, level.name), retries: 0);

  @override
  Future<Result<void>> clearHistory() => guard(() async {
    await _sessions.clear();
    for (final key in [chosenDayKey, legacyChosenDayKey, draftKey, levelKey]) {
      await _kv.remove(key);
    }
  }, retries: 0);

  String? _stringOf(String key) {
    final value = _kv.get(key);
    return value is String ? value : null;
  }

  static T _parse<T>(T Function() parse) => parseStored(parse);

  static Map<String, Object?> _decodeMap(String raw) => decodeStoredMap(raw);
}
