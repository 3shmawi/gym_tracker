import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_media.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_media_repository.dart';

/// Used until `Dependencies.init` runs, in widget tests and without Supabase
/// values: there is no server, so the phone's copy (if any) is all there is.
class UnconfiguredGymMediaRepository implements GymMediaRepository {
  const new();

  @override
  Future<Result<GymMedia>> fetch(String gymId) async =>
      const Failed(NetworkFailure());
}

class InMemoryGymMediaStore implements GymMediaStore {
  final Map<String, GymMedia> _data = {};

  @override
  Future<Result<GymMedia?>> load(String gymId) async => Success(_data[gymId]);

  @override
  Future<Result<void>> save(String gymId, GymMedia media) async {
    _data[gymId] = media;
    return const Success(null);
  }

  @override
  Future<Result<void>> clear(String gymId) async {
    _data.remove(gymId);
    return const Success(null);
  }
}
