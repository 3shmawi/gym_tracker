import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_media.dart';

/// What the gym chose to show on its exercise screens, on the server.
abstract interface class GymMediaRepository {
  /// Every picture of [gymId] the caller may read (RLS: the gym's active
  /// members). An empty gym is [GymMedia.empty], not a failure.
  Future<Result<GymMedia>> fetch(String gymId);
}

/// The phone's copy of each gym's media, so exercise screens work offline.
abstract interface class GymMediaStore {
  Future<Result<GymMedia?>> load(String gymId);
  Future<Result<void>> save(String gymId, GymMedia media);
  Future<Result<void>> clear(String gymId);
}
