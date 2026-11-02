import 'dart:convert';

import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_draft.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/usecases/plan_rules.dart';
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
  static const chosenDayKey = 'workout.next_day';

  /// Before days had ids the chosen day was its 0-based position (int).
  /// Read once as `day-<n>` (see `legacyDayId`), removed on the next save.
  static const legacyChosenDayKey = 'workout.chosen_day';
  static const draftKey = 'workout.draft';
  static const levelKey = 'workout.level';

  /// Oldest sessions are dropped beyond this; suggestions only need the
  /// latest one per exercise.
  static const maxHistory = 200;

  @override
  Future<Result<WorkoutPlan?>> loadPlan() => guard(() async {
    final raw = _prefs.getString(planKey);
    if (raw == null) return null;
    return _parse<WorkoutPlan>(() => WorkoutPlan.fromJson(_decodeMap(raw)));
  }, retries: 0);

  /// Refuses (`ValidationFailure`) a plan outside `PlanLimits`: no days,
  /// empty or long names, targets out of range, repeated ids. Names are
  /// stored as JSON text, never interpreted.
  @override
  Future<Result<void>> savePlan(WorkoutPlan plan) => guard(() async {
    final problem = validatePlan(plan);
    if (problem != null) throw FormatException('invalid plan: $problem');
    await _prefs.setString(planKey, jsonEncode(plan.toJson()));
  }, retries: 0);

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
    await _prefs.remove(legacyChosenDayKey);
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

  /// A stored value of the wrong shape reads as no choice (the plan then
  /// follows the history) rather than an error screen.
  @override
  Future<Result<ChosenDay?>> loadChosenDay() => guard(() async {
    final raw = _prefs.get(chosenDayKey);
    if (raw is String) {
      try {
        return ChosenDay.fromJson(jsonDecode(raw));
      } on FormatException {
        return null;
      }
    }
    final legacy = _prefs.get(legacyChosenDayKey);
    return legacy is int && legacy >= 0 ? ChosenDay(legacyDayId(legacy)) : null;
  }, retries: 0);

  @override
  Future<Result<void>> saveChosenDay(ChosenDay? day) => guard(() async {
    await _prefs.remove(legacyChosenDayKey);
    if (day == null) {
      await _prefs.remove(chosenDayKey);
    } else {
      await _prefs.setString(chosenDayKey, jsonEncode(day.toJson()));
    }
  }, retries: 0);

  @override
  Future<Result<Level>> loadBestLevel() => guard(
    // Anything unexpected (another type, an unknown name) is a beginner.
    () async => Level.fromName(_prefs.get(levelKey)?.toString()),
    retries: 0,
  );

  @override
  Future<Result<void>> saveBestLevel(Level level) =>
      guard(() => _prefs.setString(levelKey, level.name), retries: 0);

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
