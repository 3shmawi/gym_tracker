import 'dart:convert';

import 'package:gym_tracker/features/workout/data/local/stored_json.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The small values of the workout repository (plan, draft, chosen day,
/// level): a few strings. Reads are synchronous (kept in memory); writes
/// reach the phone's storage before they return.
abstract interface class WorkoutKv {
  /// The stored value, or null. A [String] unless an old release stored
  /// another type (the chosen day used to be an int).
  Object? get(String key);

  Future<void> set(String key, String value);

  Future<void> remove(String key);
}

/// Finished workouts, oldest first. Each store decides how they are kept.
abstract interface class SessionStore {
  /// Every workout. Throws a [FormatException] for unreadable stored data.
  Future<List<WorkoutSession>> readAll();

  Future<void> add(WorkoutSession session);

  Future<void> clear();
}

/// [WorkoutKv] on SharedPreferences (the phone's original storage).
class PrefsWorkoutKv implements WorkoutKv {
  new(this._prefs);

  final SharedPreferences _prefs;

  @override
  Object? get(String key) => _prefs.get(key);

  @override
  Future<void> set(String key, String value) => _prefs.setString(key, value);

  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

/// [SessionStore] on SharedPreferences: one JSON list, cut to the last
/// [maxHistory]. The fallback when the database cannot be opened.
class PrefsSessionStore implements SessionStore {
  new(this._prefs);

  final SharedPreferences _prefs;

  static const historyKey = 'workout.history';

  /// Oldest sessions are dropped beyond this; suggestions only need the
  /// latest one per exercise.
  static const maxHistory = 200;

  @override
  Future<List<WorkoutSession>> readAll() async {
    final raw = _prefs.getString(historyKey);
    if (raw == null) return [];
    return parseHistoryJson(raw);
  }

  @override
  Future<void> add(WorkoutSession session) async {
    final history = [...await readAll(), session];
    final kept = history.length > maxHistory
        ? history.sublist(history.length - maxHistory)
        : history;
    await _prefs.setString(
      historyKey,
      jsonEncode([for (final s in kept) s.toJson()]),
    );
  }

  @override
  Future<void> clear() => _prefs.remove(historyKey);
}

/// The stored history JSON as sessions; throws a [FormatException] when the
/// whole text or any item is unreadable.
List<WorkoutSession> parseHistoryJson(String raw) {
  final list = jsonDecode(raw);
  if (list is! List<Object?>) {
    throw const FormatException('workout history is not a list');
  }
  return parseStored(
    () => [for (final item in list) WorkoutSession.fromJson(asStoredMap(item))],
  );
}
