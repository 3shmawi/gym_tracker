import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_logo_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The gyms' logos as files in the app's support folder, with an index in
/// shared preferences (docs/designs/gym_logo.md §5). Not secret: a gym's
/// logo is its public brand.
///
/// A file's name is `<gym id>-<version>.img`: both are checked (a UUID and an
/// integer), nothing else from the server reaches the file system. A new
/// file is written next to the old one, renamed into place, then the index
/// points at it, then the old file goes: a crash at any step leaves either
/// the old logo or the new one, never half a file.
class FileGymLogoStore implements GymLogoStore {
  new(this._prefs, this._folder);

  final SharedPreferences _prefs;

  /// The folder to keep the files in (created when needed).
  final Future<Directory> Function() _folder;

  static const indexKey = 'gym.logos';
  static const folderName = 'gym_logos';

  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
  );

  static String fileName(GymLogoRef logo) =>
      '${logo.gymId}-${logo.version}.img';

  Future<Directory> _dir() async {
    final dir = Directory('${(await _folder()).path}/$folderName');
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  Map<String, Object?> _readIndex() {
    final raw = _prefs.getString(indexKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, Object?> ? decoded : {};
    } on FormatException {
      return {};
    }
  }

  Future<void> _writeIndex(Map<String, Object?> index) =>
      _prefs.setString(indexKey, jsonEncode(index));

  /// An index entry, if it is well formed and for [gymId].
  static GymLogoRef? _entry(String gymId, Object? value) {
    if (!_uuid.hasMatch(gymId) || value is! Map<String, Object?>) return null;
    final path = Gym.readLogoPath(gymId, value['path']);
    final version = value['version'];
    if (path == null || version is! int || version < 0) return null;
    return GymLogoRef(gymId: gymId, path: path, version: version);
  }

  @override
  Future<Map<String, StoredGymLogo>> load() async {
    final out = <String, StoredGymLogo>{};
    try {
      // Reading never creates the folder.
      final dir = Directory('${(await _folder()).path}/$folderName');
      if (!dir.existsSync()) return out;
      for (final MapEntry(:key, :value) in _readIndex().entries) {
        final logo = _entry(key, value);
        if (logo == null) continue;
        final file = File('${dir.path}/${fileName(logo)}');
        if (file.existsSync()) {
          out[key] = StoredGymLogo(logo: logo, filePath: file.path);
        }
      }
    } on Object {
      // No folder (or no access): no logos, the tiles show letters.
    }
    return out;
  }

  @override
  Future<Result<StoredGymLogo>> save(GymLogoRef logo, Uint8List bytes) =>
      guard(() async {
        if (!_uuid.hasMatch(logo.gymId) || logo.version < 0) {
          throw const FormatException('logo ref');
        }
        final dir = await _dir();
        final target = File('${dir.path}/${fileName(logo)}');
        final temp = File('${target.path}.tmp');
        await temp.writeAsBytes(bytes, flush: true);
        await temp.rename(target.path);

        final index = _readIndex();
        final previous = _entry(logo.gymId, index[logo.gymId]);
        index[logo.gymId] = {'path': logo.path, 'version': logo.version};
        await _writeIndex(index);
        if (previous != null && fileName(previous) != fileName(logo)) {
          await _delete(File('${dir.path}/${fileName(previous)}'));
        }
        await _sweep(dir, index);
        return StoredGymLogo(logo: logo, filePath: target.path);
      }, retries: 0);

  @override
  Future<Result<void>> remove(String gymId) => guard(() async {
    final index = _readIndex();
    final previous = _entry(gymId, index.remove(gymId));
    await _writeIndex(index);
    if (previous != null) {
      await _delete(File('${(await _dir()).path}/${fileName(previous)}'));
    }
  }, retries: 0);

  @override
  Future<Result<void>> clear() => guard(() async {
    await _prefs.remove(indexKey);
    final dir = Directory('${(await _folder()).path}/$folderName');
    if (dir.existsSync()) await dir.delete(recursive: true);
  }, retries: 0);

  /// Deletes files the index does not point at (left by a crash between
  /// two steps of a save).
  Future<void> _sweep(Directory dir, Map<String, Object?> index) async {
    final keep = {
      for (final MapEntry(:key, :value) in index.entries)
        if (_entry(key, value) case final logo?) fileName(logo),
    };
    await for (final f in dir.list()) {
      final name = f.uri.pathSegments.last;
      if (f is File && !keep.contains(name)) await _delete(f);
    }
  }

  static Future<void> _delete(File file) async {
    try {
      if (file.existsSync()) await file.delete();
    } on FileSystemException {
      // Gone already, or locked: the next sweep tries again.
    }
  }
}
