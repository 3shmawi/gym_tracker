import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/solo_import.dart';
import 'package:gym_tracker/features/gym/domain/repositories/solo_import_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The solo-import choice and progress on the phone. Not secret.
class PrefsSoloImportStore implements SoloImportStore {
  const new(this._prefs);

  final SharedPreferences _prefs;

  static const choiceKey = 'gym.solo_import.choice';
  static const indexKey = 'gym.solo_import.index';
  static const migratedKey = 'gym.solo_import.migrated_at';

  @override
  Future<Result<SoloImportStatus>> load() => guard(() async {
    final name = _prefs.getString(choiceKey);
    final migrated = _prefs.getString(migratedKey);
    final index = _prefs.getInt(indexKey);
    return SoloImportStatus(
      choice: SoloImportChoice.values.firstWhere(
        (c) => c.name == name,
        orElse: () => SoloImportChoice.undecided,
      ),
      nextIndex: index == null || index < 0 ? 0 : index,
      migratedAt: migrated == null ? null : DateTime.tryParse(migrated),
    );
  }, retries: 0);

  @override
  Future<Result<void>> save(SoloImportStatus status) => guard(() async {
    await _prefs.setString(choiceKey, status.choice.name);
    await _prefs.setInt(indexKey, status.nextIndex);
    final at = status.migratedAt;
    if (at == null) {
      await _prefs.remove(migratedKey);
    } else {
      await _prefs.setString(migratedKey, at.toUtc().toIso8601String());
    }
  }, retries: 0);

  @override
  Future<Result<void>> clear() => guard(() async {
    await _prefs.remove(choiceKey);
    await _prefs.remove(indexKey);
    await _prefs.remove(migratedKey);
  }, retries: 0);
}
