import 'package:meta/meta.dart';

/// The joints the rep detectors use. The data layer maps the pose model's
/// own ids to these; nothing else in the app knows the model.
enum PoseJoint {
  nose,
  leftShoulder,
  rightShoulder,
  leftElbow,
  rightElbow,
  leftWrist,
  rightWrist,
  leftHip,
  rightHip,
  leftKnee,
  rightKnee,
  leftAnkle,
  rightAnkle,
}

/// One joint in one camera frame.
///
/// [x] and [y] are fractions of the upright image (0..1, y grows down). The
/// model puts joints it cannot see **outside** 0..1, so values a little out
/// of range are normal. [likelihood] is the model's confidence that the
/// joint is in the frame (0..1).
@immutable
class Landmark {
  const new({required this.x, required this.y, required this.likelihood});

  final double x;
  final double y;
  final double likelihood;

  /// Numbers a detector can trust at all: finite, likelihood 0..1, and not
  /// absurdly far outside the image (a broken frame, not a hidden joint).
  bool get isSane =>
      x.isFinite &&
      y.isFinite &&
      likelihood.isFinite &&
      likelihood >= 0 &&
      likelihood <= 1 &&
      x >= -1 &&
      x <= 2 &&
      y >= -1 &&
      y <= 2;

  /// Inside the image.
  bool get isInFrame => x >= 0 && x <= 1 && y >= 0 && y <= 1;

  @override
  bool operator ==(Object other) =>
      other is Landmark &&
      other.x == x &&
      other.y == y &&
      other.likelihood == likelihood;

  @override
  int get hashCode => Object.hash(x, y, likelihood);

  @override
  String toString() => 'Landmark($x, $y, $likelihood)';
}

/// One processed camera frame.
///
/// [at] is the frame's own time (from the camera or the recording), so a
/// replayed recording gives exactly the same result. [joints] may miss any
/// joint. Nothing in a frame identifies a person and frames are never kept.
@immutable
class PoseFrame {
  const new({
    required this.at,
    required this.joints,
    this._aspect = defaultAspect,
  });

  /// Portrait 480×640.
  static const defaultAspect = 0.75;

  final Duration at;
  final Map<PoseJoint, Landmark> joints;
  final double _aspect;

  /// Image width / height, so x and y distances can be compared. A
  /// nonsense value falls back to [defaultAspect].
  double get aspect => _aspect.isFinite && _aspect >= 0.2 && _aspect <= 5
      ? _aspect
      : defaultAspect;

  /// The joint when it is sane, inside the image and seen with at least
  /// [minLikelihood]; otherwise null.
  Landmark? seen(PoseJoint joint, {double minLikelihood = 0.5}) {
    final l = joints[joint];
    if (l == null || !l.isSane || !l.isInFrame) return null;
    return l.likelihood >= minLikelihood ? l : null;
  }

  /// The joint when its numbers are sane, wherever it is (also outside the
  /// image) and however unsure the model is; otherwise null.
  Landmark? raw(PoseJoint joint) {
    final l = joints[joint];
    return l != null && l.isSane ? l : null;
  }
}
