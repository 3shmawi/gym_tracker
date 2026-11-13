import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/move_sound_mode.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/domain/repositories/move_local_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [MoveLocalRepository] in shared preferences: a few numbers and flags.
class PrefsMoveLocalRepository implements MoveLocalRepository {
  const new(this._prefs);

  final SharedPreferences _prefs;

  static String bestKey(MoveExerciseId e, RoundKind k) =>
      'move.best.${e.id}.${k.id}';
  static String tipKey(MoveExerciseId e) => 'move.tip_seen.${e.id}';
  static const cameraKey = 'move.camera_allowed';
  static const soundKey = 'move.sound_mode';

  /// Before the spoken count: a bool, false when muted.
  static const legacySoundKey = 'move.sound_on';

  /// A stored value outside 0..999 (a corrupt or edited file) is ignored.
  static int? _sane(Object? v) => v is int && v > 0 && v <= 999 ? v : null;

  @override
  Future<Result<int?>> best(MoveExerciseId exercise, RoundKind kind) =>
      guard(() async => _sane(_prefs.get(bestKey(exercise, kind))), retries: 0);

  @override
  Future<Result<bool>> offerBest(
    MoveExerciseId exercise,
    RoundKind kind,
    int reps,
  ) => guard(() async {
    if (reps <= 0 || reps > 999) return false;
    final key = bestKey(exercise, kind);
    final current = _sane(_prefs.get(key));
    if (current != null && reps <= current) return false;
    await _prefs.setInt(key, reps);
    return true;
  }, retries: 0);

  @override
  Future<Result<bool>> tipSeen(MoveExerciseId exercise) =>
      guard(() async => _prefs.get(tipKey(exercise)) == true, retries: 0);

  @override
  Future<Result<void>> markTipSeen(MoveExerciseId exercise) =>
      guard(() => _prefs.setBool(tipKey(exercise), true), retries: 0);

  @override
  Future<Result<bool>> cameraAllowedBefore() =>
      guard(() async => _prefs.get(cameraKey) == true, retries: 0);

  @override
  Future<Result<void>> markCameraAllowed() =>
      guard(() => _prefs.setBool(cameraKey, true), retries: 0);

  /// A stored id, or "off" for a round muted before the spoken count;
  /// anything else is the default.
  @override
  Future<Result<MoveSoundMode>> soundMode() => guard(() async {
    final stored = _prefs.get(soundKey);
    if (stored is String) return MoveSoundMode.fromId(stored);
    if (_prefs.get(legacySoundKey) == false) return MoveSoundMode.off;
    return MoveSoundMode.fallback;
  }, retries: 0);

  @override
  Future<Result<void>> setSoundMode(MoveSoundMode mode) =>
      guard(() => _prefs.setString(soundKey, mode.id), retries: 0);
}

/// In memory: tests, and before `Dependencies.init`.
class InMemoryMoveLocalRepository implements MoveLocalRepository {
  final Map<String, int> bests = {};
  final Set<MoveExerciseId> tips = {};
  bool camera = false;
  MoveSoundMode sound = MoveSoundMode.fallback;

  @override
  Future<Result<int?>> best(MoveExerciseId exercise, RoundKind kind) async =>
      Success(bests['${exercise.id}.${kind.id}']);

  @override
  Future<Result<bool>> offerBest(
    MoveExerciseId exercise,
    RoundKind kind,
    int reps,
  ) async {
    final key = '${exercise.id}.${kind.id}';
    final current = bests[key];
    if (reps <= 0 || (current != null && reps <= current)) {
      return const Success(false);
    }
    bests[key] = reps;
    return const Success(true);
  }

  @override
  Future<Result<bool>> tipSeen(MoveExerciseId exercise) async =>
      Success(tips.contains(exercise));

  @override
  Future<Result<void>> markTipSeen(MoveExerciseId exercise) async {
    tips.add(exercise);
    return const Success(null);
  }

  @override
  Future<Result<bool>> cameraAllowedBefore() async => Success(camera);

  @override
  Future<Result<void>> markCameraAllowed() async {
    camera = true;
    return const Success(null);
  }

  @override
  Future<Result<MoveSoundMode>> soundMode() async => Success(sound);

  @override
  Future<Result<void>> setSoundMode(MoveSoundMode mode) async {
    sound = mode;
    return const Success(null);
  }
}
