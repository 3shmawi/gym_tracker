import 'package:gym_tracker/features/backup/domain/entities/restore.dart';
import 'package:gym_tracker/features/gym/domain/usecases/restore_gym_history.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [GymHistoryCursorStore] in shared preferences (not secret: a time and a
/// row id). Cleared with the rest of the gym state on the phone.
class PrefsGymHistoryCursor implements GymHistoryCursorStore {
  new(this._prefs, {DateTime Function()? now}) : _now = now ?? DateTime.now;

  final SharedPreferences _prefs;
  final DateTime Function() _now;

  static const cursorKey = 'gym.history_restore';
  static const lastKey = 'gym.history_restore.last';
  static const addedKey = 'gym.history_restore.added';
  static const doneAtKey = 'gym.history_restore.done_at';
  static const List<String> keys = [cursorKey, lastKey, addedKey, doneAtKey];

  @override
  String? read() => _prefs.getString(cursorKey);

  @override
  Future<void> write(String? value) async {
    if (value == null) {
      await _prefs.remove(cursorKey);
      return;
    }
    await _prefs.setString(cursorKey, value);
    if (value == RestoreCursor.done) {
      await _prefs.setString(doneAtKey, _now().toUtc().toIso8601String());
    } else if (RestoreCursor.parse(value) != null) {
      await _prefs.setString(lastKey, value);
    }
  }

  @override
  int get added {
    final v = _prefs.get(addedKey);
    return v is int && v >= 0 && v <= 1000000 ? v : 0;
  }

  @override
  Future<void> setAdded(int value) => _prefs.setInt(addedKey, value);

  @override
  DateTime? get doneAt {
    final v = _prefs.get(doneAtKey);
    return v is String ? DateTime.tryParse(v) : null;
  }

  @override
  Future<void> reopen() async {
    final last = _prefs.getString(lastKey);
    if (RestoreCursor.parse(last) == null) {
      await _prefs.remove(cursorKey);
    } else {
      await _prefs.setString(cursorKey, last!);
    }
  }

  @override
  Future<void> clear() async {
    for (final k in keys) {
      await _prefs.remove(k);
    }
  }
}

/// In memory (tests, and until `Dependencies.init`).
class InMemoryGymHistoryCursor implements GymHistoryCursorStore {
  new({DateTime Function()? now}) : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  String? cursor;
  String? last;
  int _added = 0;
  DateTime? _doneAt;

  @override
  String? read() => cursor;

  @override
  Future<void> write(String? value) async {
    cursor = value;
    if (value == RestoreCursor.done) {
      _doneAt = _now();
    } else if (RestoreCursor.parse(value) != null) {
      last = value;
    }
  }

  @override
  int get added => _added;

  @override
  Future<void> setAdded(int value) async => _added = value;

  @override
  DateTime? get doneAt => _doneAt;

  @override
  Future<void> reopen() async =>
      cursor = RestoreCursor.parse(last) == null ? null : last;

  @override
  Future<void> clear() async {
    cursor = null;
    last = null;
    _added = 0;
    _doneAt = null;
  }
}
