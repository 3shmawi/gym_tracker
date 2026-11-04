import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_media.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_media_repository.dart';

/// The pictures a solo member chose (no gym, no captain): kept only on the
/// phone, in the same shape and limits as a gym's (6 per exercise). Field
/// test 2026-11-03: solo members wanted what captains have.
class SoloPictures {
  const new(this._store);

  final GymMediaStore _store;

  /// The store key; a gym id is a uuid, so they never clash.
  static const storeId = 'solo';

  Future<GymMedia> load() async => switch (await _store.load(storeId)) {
    Success(:final value) => value ?? GymMedia.empty,
    Failed() => GymMedia.empty,
  };

  /// Replaces [exerciseId]'s pictures with [publicIds] in that order (first
  /// = cover). Invalid ids are dropped; more than 6 are cut. Empty removes
  /// them. Returns what was saved.
  Future<Result<GymMedia>> choose(
    String exerciseId,
    List<String> publicIds,
  ) async {
    if (!GymExercisePicture.exerciseIdPattern.hasMatch(exerciseId)) {
      return const Failed(UnknownFailure('exercise id'));
    }
    final current = await load();
    final chosen = <GymExercisePicture>[
      for (final (i, id)
          in publicIds
              .where(GymExercisePicture.publicIdPattern.hasMatch)
              .toSet()
              .take(GymMedia.maxPicturesPerExercise)
              .indexed)
        GymExercisePicture(
          exerciseId: exerciseId,
          publicId: id,
          position: i + 1,
        ),
    ];
    final media = GymMedia.fromPictures([
      for (final p in current.allPictures)
        if (p.exerciseId != exerciseId) p,
      ...chosen,
    ]);
    return switch (await _store.save(storeId, media)) {
      Success() => Success(media),
      Failed(:final failure) => Failed(failure),
    };
  }
}
