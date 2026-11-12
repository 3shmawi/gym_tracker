import 'package:gym_tracker/features/backup/domain/repositories/backup_repositories.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [BackupSettings] on SharedPreferences (small values; no secrets: the
/// session lives in the secure store).
class PrefsBackupSettings implements BackupSettings {
  new(this._prefs);

  final SharedPreferences _prefs;

  static const enabledKey = 'backup.enabled';
  static const lastKey = 'backup.last_synced';
  static const planVersionKey = 'backup.plan_version';
  static const planFingerprintKey = 'backup.plan_fingerprint';
  static const planConflictKey = 'backup.plan_conflict';
  static const stateFingerprintKey = 'backup.state_fingerprint';
  static const restoreCursorKey = 'backup.restore_cursor';
  static const keptPlanKey = 'backup.kept_plan';
  static const keptPlanAtKey = 'backup.kept_plan_at';

  @override
  bool get enabled => _prefs.getBool(enabledKey) ?? false;

  @override
  Future<void> setEnabled({required bool value}) =>
      _prefs.setBool(enabledKey, value);

  @override
  DateTime? get lastSyncedAt {
    final ms = _prefs.getInt(lastKey);
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  @override
  Future<void> setLastSyncedAt(DateTime at) =>
      _prefs.setInt(lastKey, at.millisecondsSinceEpoch);

  @override
  int get planVersion => _prefs.getInt(planVersionKey) ?? 0;

  @override
  String? get planFingerprint => _prefs.getString(planFingerprintKey);

  @override
  Future<void> setPlan({
    required int version,
    required String fingerprint,
  }) async {
    await _prefs.setInt(planVersionKey, version);
    await _prefs.setString(planFingerprintKey, fingerprint);
  }

  @override
  bool get planConflict => _prefs.getBool(planConflictKey) ?? false;

  @override
  Future<void> setPlanConflict({required bool value}) =>
      _prefs.setBool(planConflictKey, value);

  @override
  String? get stateFingerprint => _prefs.getString(stateFingerprintKey);

  @override
  Future<void> setStateFingerprint(String fingerprint) =>
      _prefs.setString(stateFingerprintKey, fingerprint);

  @override
  String? get restoreCursor => _prefs.getString(restoreCursorKey);

  @override
  Future<void> setRestoreCursor(String? value) async {
    if (value == null) {
      await _prefs.remove(restoreCursorKey);
    } else {
      await _prefs.setString(restoreCursorKey, value);
    }
  }

  @override
  String? get keptPlan => _prefs.getString(keptPlanKey);

  @override
  DateTime? get keptPlanAt {
    final ms = _prefs.getInt(keptPlanAtKey);
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  @override
  Future<void> setKeptPlan(String? json, DateTime at) async {
    if (json == null) {
      await _prefs.remove(keptPlanKey);
      await _prefs.remove(keptPlanAtKey);
    } else {
      await _prefs.setString(keptPlanKey, json);
      await _prefs.setInt(keptPlanAtKey, at.millisecondsSinceEpoch);
    }
  }
}
