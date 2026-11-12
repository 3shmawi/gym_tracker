import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:gym_tracker/features/move/data/datasources/landmark_mapping.dart';
import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';

PoseLandmark lm(PoseLandmarkType t, double x, double y, double l) =>
    PoseLandmark(type: t, x: x, y: y, z: 0, likelihood: l);

void main() {
  group('poseFrameFrom', () {
    test('pixels become fractions of the upright image', () {
      final frame = poseFrameFrom(
        {
          PoseLandmarkType.leftShoulder: lm(
            PoseLandmarkType.leftShoulder,
            240,
            320,
            0.9,
          ),
          PoseLandmarkType.rightWrist: lm(
            PoseLandmarkType.rightWrist,
            480,
            0,
            0.4,
          ),
        },
        at: const Duration(milliseconds: 500),
        width: 480,
        height: 640,
      );
      expect(frame.at, const Duration(milliseconds: 500));
      expect(frame.aspect, 0.75);
      expect(
        frame.joints[PoseJoint.leftShoulder],
        const Landmark(x: 0.5, y: 0.5, likelihood: 0.9),
      );
      expect(
        frame.joints[PoseJoint.rightWrist],
        const Landmark(x: 1, y: 0, likelihood: 0.4),
      );
    });

    test('keeps only the 13 joints the detectors use', () {
      final all = {
        for (final t in PoseLandmarkType.values) t: lm(t, 10, 10, 1),
      };
      final frame = poseFrameFrom(
        all,
        at: Duration.zero,
        width: 100,
        height: 100,
      );
      expect(frame.joints.keys.toSet(), PoseJoint.values.toSet());
      expect(mlKitJoints, hasLength(PoseJoint.values.length));
    });

    test('no pose, or a broken image size, gives an empty frame', () {
      for (final (landmarks, w, h) in [
        (null, 480.0, 640.0),
        (<PoseLandmarkType, PoseLandmark>{}, 480.0, 640.0),
        (
          {PoseLandmarkType.nose: lm(PoseLandmarkType.nose, 1, 1, 1)},
          0.0,
          640.0,
        ),
        (
          {PoseLandmarkType.nose: lm(PoseLandmarkType.nose, 1, 1, 1)},
          480.0,
          -1.0,
        ),
      ]) {
        final frame = poseFrameFrom(
          landmarks,
          at: Duration.zero,
          width: w,
          height: h,
        );
        expect(frame.joints, isEmpty);
      }
    });
  });

  group('androidRotation (ML Kit sample formula)', () {
    test('front camera adds the device turn to the sensor angle', () {
      expect(
        androidRotation(sensorOrientation: 270, deviceDegrees: 0, front: true),
        270,
      );
      expect(
        androidRotation(sensorOrientation: 270, deviceDegrees: 90, front: true),
        0,
      );
      expect(
        androidRotation(
          sensorOrientation: 270,
          deviceDegrees: 270,
          front: true,
        ),
        180,
      );
    });

    test('back camera subtracts it', () {
      expect(
        androidRotation(sensorOrientation: 90, deviceDegrees: 90, front: false),
        0,
      );
      expect(
        androidRotation(sensorOrientation: 90, deviceDegrees: 0, front: false),
        90,
      );
    });

    test('odd sensor values snap to a quarter turn', () {
      expect(
        androidRotation(sensorOrientation: 95, deviceDegrees: 0, front: true),
        90,
      );
    });
  });

  test('uprightSize swaps width and height on a quarter turn', () {
    expect(uprightSize(640, 480, 0), (width: 640.0, height: 480.0));
    expect(uprightSize(640, 480, 90), (width: 480.0, height: 640.0));
    expect(uprightSize(640, 480, 180), (width: 640.0, height: 480.0));
    expect(uprightSize(640, 480, 270), (width: 480.0, height: 640.0));
  });
}
