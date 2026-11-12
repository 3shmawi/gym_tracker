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
