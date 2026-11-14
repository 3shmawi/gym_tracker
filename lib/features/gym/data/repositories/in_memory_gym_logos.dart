import 'dart:typed_data';

import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_logo_repository.dart';

/// Used until `Dependencies.init` runs, in widget tests and without Supabase
/// values: no logo can be downloaded, every tile shows letters.
class UnconfiguredGymLogoRepository implements GymLogoRepository {
  const new();

  @override
  Future<Result<Uint8List>> fetch(GymLogoRef logo) async =>
      const Failed(NetworkFailure());
}

/// Logos kept in memory (tests, and until `Dependencies.init`). The "file"
/// is a made-up path; a test shows the bytes with [bytesOf].
class InMemoryGymLogoStore implements GymLogoStore {
  final Map<String, (GymLogoRef, Uint8List)> _logos = {};

  Uint8List? bytesOf(String gymId) => _logos[gymId]?.$2;

  static String pathOf(GymLogoRef logo) =>
      'memory/${logo.gymId}-${logo.version}.img';

  @override
  Future<Map<String, StoredGymLogo>> load() async => {
    for (final MapEntry(:key, value: (logo, _)) in _logos.entries)
      key: StoredGymLogo(logo: logo, filePath: pathOf(logo)),
  };

  @override
  Future<Result<StoredGymLogo>> save(GymLogoRef logo, Uint8List bytes) async {
    _logos[logo.gymId] = (logo, bytes);
    return Success(StoredGymLogo(logo: logo, filePath: pathOf(logo)));
  }

  @override
  Future<Result<void>> remove(String gymId) async {
    _logos.remove(gymId);
    return const Success(null);
  }

  @override
  Future<Result<void>> clear() async {
    _logos.clear();
    return const Success(null);
  }
}
