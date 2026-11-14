import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:meta/meta.dart';

/// Why there are no frames.
enum PoseProblem {
  /// The member said no to the camera (or it is blocked by the system).
  denied,

  /// No front camera, or it failed to start.
  noCamera,

  /// The pose model could not load or run on this phone.
  modelFailed,
}

enum PoseSourceState { idle, starting, running, failed }

/// The source's state, with the measured speed while running.
@immutable
class PoseSourceStatus {
  const new(this.state, {this.problem, this.fps});

  static const idle = PoseSourceStatus(PoseSourceState.idle);

  final PoseSourceState state;

  /// Set when [state] is failed.
  final PoseProblem? problem;

  /// Frames the model finished per second, over the last few seconds.
  final double? fps;

  @override
  bool operator ==(Object other) =>
      other is PoseSourceStatus &&
      other.state == state &&
      other.problem == problem &&
      other.fps == fps;

  @override
  int get hashCode => Object.hash(state, problem, fps);
}

/// The front camera's zoom: what the phone allows and where it is now.
/// Many front cameras go no wider than 1×; some go below (0.6×–0.8×).
@immutable
class CameraZoom {
  const new({required this.min, required this.max, required this.level});

  final double min;
  final double max;
  final double level;

  /// One tap of − or +.
  static const step = 0.25;

  /// The highest level offered: more only crops the picture, and a body
  /// that fills less of it is counted worse.
  static const maxOffered = 3.0;

  /// The top of the range the member can reach.
  double get top => max < maxOffered ? max : maxOffered;

  /// Whether there is anything to choose (some phones report 1×–1×).
  bool get adjustable => top - min >= 0.05;

  bool get atWidest => level <= min + 0.001;
  bool get atClosest => level >= top - 0.001;

  /// [value] kept inside what the phone allows ([min]…[top]); a value that
  /// is not a number is the widest.
  double clamp(double value) {
    if (!value.isFinite) return min;
    if (value < min) return min;
    return value > top ? top : value;
  }

  CameraZoom at(double value) =>
      CameraZoom(min: min, max: max, level: clamp(value));

  @override
  bool operator ==(Object other) =>
      other is CameraZoom &&
      other.min == min &&
      other.max == max &&
      other.level == level;

  @override
  int get hashCode => Object.hash(min, max, level);
}

/// A source whose camera can zoom (the real camera; not recordings).
abstract interface class ZoomablePoseSource implements PoseSource {
  /// Null until the camera runs, or when the phone reports no range.
  CameraZoom? get zoom;

  /// Moves the zoom (kept inside the range); returns where it is now.
  Future<CameraZoom?> setZoom(double level);
}

/// Where pose frames come from: the camera and the on-device model in the
/// app, a recording or a synthetic sequence in tests and demos. Frames are
/// used and dropped; a source never stores or sends them.
abstract interface class PoseSource {
  /// At most about 15 frames a second, in time order.
  Stream<PoseFrame> get frames;

  Stream<PoseSourceStatus> get status;
  PoseSourceStatus get currentStatus;

  /// Starts the camera and the model. Asks for the camera permission the
  /// first time, so call it only after the member asked for the camera.
  Future<void> start();

  /// Releases the camera and the model. Safe to call at any time.
  Future<void> stop();
}
