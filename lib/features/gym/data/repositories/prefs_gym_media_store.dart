import 'dart:convert';

import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_media.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_media_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Each gym's media, for offline use, in shared preferences (not secret:
/// which library pictures the gym chose; no personal data).
class PrefsGymMediaStore implements GymMediaStore {
  const new(this._prefs);

  final SharedPreferences _prefs;

  static String key(String gymId) => 'gym.media.$gymId';

  static bool _safe(String id) => RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(id);

  @override
  Future<Result<GymMedia?>> load(String gymId) => guard(() async {
    if (!_safe(gymId)) return null;
    final raw = _prefs.getString(key(gymId));
    if (raw == null) return null;
    try {
      return GymMedia.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }, retries: 0);

  @override
  Future<Result<void>> save(String gymId, GymMedia media) => guard(() async {
    if (!_safe(gymId)) throw const FormatException('gym id');
    await _prefs.setString(key(gymId), jsonEncode(media.toJson()));
  }, retries: 0);

  @override
  Future<Result<void>> clear(String gymId) => guard(() async {
    if (!_safe(gymId)) return;
    await _prefs.remove(key(gymId));
  }, retries: 0);
}
