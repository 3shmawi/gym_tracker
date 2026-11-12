import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';

/// The ML Kit landmarks the detectors use.
const mlKitJoints = <PoseLandmarkType, PoseJoint>{
  PoseLandmarkType.nose: PoseJoint.nose,
  PoseLandmarkType.leftShoulder: PoseJoint.leftShoulder,
  PoseLandmarkType.rightShoulder: PoseJoint.rightShoulder,
  PoseLandmarkType.leftElbow: PoseJoint.leftElbow,
  PoseLandmarkType.rightElbow: PoseJoint.rightElbow,
  PoseLandmarkType.leftWrist: PoseJoint.leftWrist,
  PoseLandmarkType.rightWrist: PoseJoint.rightWrist,
  PoseLandmarkType.leftHip: PoseJoint.leftHip,
  PoseLandmarkType.rightHip: PoseJoint.rightHip,
  PoseLandmarkType.leftKnee: PoseJoint.leftKnee,
  PoseLandmarkType.rightKnee: PoseJoint.rightKnee,
  PoseLandmarkType.leftAnkle: PoseJoint.leftAnkle,
  PoseLandmarkType.rightAnkle: PoseJoint.rightAnkle,
};

/// One ML Kit result as a [PoseFrame]: pixel coordinates in the upright
/// image ([width] × [height]) become fractions; other landmarks (eyes,
/// fingers, heels) are dropped. No pose = an empty frame.
PoseFrame poseFrameFrom(
  Map<PoseLandmarkType, PoseLandmark>? landmarks, {
  required Duration at,
  required double width,
  required double height,
}) {
  if (landmarks == null || width <= 0 || height <= 0) {
    return PoseFrame(at: at, joints: const {});
  }
  return PoseFrame(
    at: at,
    aspect: width / height,
    joints: {
      for (final MapEntry(key: type, value: joint) in mlKitJoints.entries)
        if (landmarks[type] case final l?)
          joint: Landmark(
            x: l.x / width,
            y: l.y / height,
            likelihood: l.likelihood,
          ),
    },
  );
}

/// How many degrees the camera image must turn to be upright, as ML Kit
/// wants it on Android (ML Kit's own sample): the sensor's mounting angle
/// combined with how the phone is held. iOS frames already come upright
/// (the camera plugin rotates the connection), so this is Android only.
int androidRotation({
  required int sensorOrientation,
  required int deviceDegrees,
  required bool front,
}) {
  final rotation = front
      ? (sensorOrientation + deviceDegrees) % 360
      : (sensorOrientation - deviceDegrees + 360) % 360;
  return rotation - rotation % 90;
}

/// The upright image size after turning [rotation] degrees.
({double width, double height}) uprightSize(
  int width,
  int height,
  int rotation,
) => rotation % 180 == 0
    ? (width: width.toDouble(), height: height.toDouble())
    : (width: height.toDouble(), height: width.toDouble());
