import 'package:meta/meta.dart';

/// One picture of the shared picture library, as the exercise screen needs
/// it: the library's public id, and which exercise and frame it shows when
/// the id follows `exercises/ek-<id>-<frame>`.
@immutable
class LibraryPictureRef {
  const new({required this.publicId, this.exerciseKey, this.frame});

  final String publicId;

  /// `ek-0055`: the library exercise the picture shows.
  final String? exerciseKey;

  /// `tension` (start of the move) or `relaxation` (end).
  final String? frame;

  @override
  bool operator ==(Object other) =>
      other is LibraryPictureRef && other.publicId == publicId;

  @override
  int get hashCode => publicId.hashCode;
}

/// Where an exercise's pictures come from, in this order:
/// the gym's pictures (by position), then the bundled picture, then the
/// library placeholder.
enum PictureSource { gym, bundled, placeholder }

/// The pictures an exercise screen shows (docs/features/gym_exercise_images.md).
@immutable
class ExercisePictures {
  const new({required this.gym, required this.hasBundled});

  /// The gym's choice, cover first (already limited to 6 by the data layer).
  final List<LibraryPictureRef> gym;

  /// The app has its own drawing of this exercise.
  final bool hasBundled;

  PictureSource get source => gym.isNotEmpty
      ? PictureSource.gym
      : hasBundled
      ? PictureSource.bundled
      : PictureSource.placeholder;

  /// Auto-advance only when the pictures are exactly the two frames of one
  /// exercise (its start and its end). Unrelated pictures only swipe.
  bool get isMovePair =>
      gym.length == 2 &&
      gym[0].exerciseKey != null &&
      gym[0].exerciseKey == gym[1].exerciseKey &&
      gym[0].frame != null &&
      gym[1].frame != null &&
      gym[0].frame != gym[1].frame;

  /// The analytics bucket of how many pictures are shown: `1`, `2-3`, `4+`.
  static String countBucket(int count) => count <= 1
      ? '1'
      : count <= 3
      ? '2-3'
      : '4+';
}
