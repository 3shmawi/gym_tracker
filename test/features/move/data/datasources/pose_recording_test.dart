import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/move/data/datasources/pose_recording.dart';
import 'package:gym_tracker/features/move/data/datasources/recorded_pose_source.dart';
import 'package:gym_tracker/features/move/domain/detectors/push_up_detector.dart';
import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:gym_tracker/features/move/domain/repositories/pose_source.dart';

import '../../helpers/synthetic_pose.dart';

void main() {
  group('PoseRecording', () {
    test('a set survives encode → decode and still counts the same', () {
      final frames = SynthSet.reps(4, noise: 0.003).frames();
      final decoded = PoseRecording.decode(PoseRecording.encode(frames));
      expect(decoded, hasLength(frames.length));
      expect(decoded.first.aspect, frames.first.aspect);
      final d = PushUpDetector();
      var reps = 0;
      for (final f in decoded) {
        reps = d.onFrame(f).state.reps;
      }
      expect(reps, 4);
    });

    test('the file holds joints and times only', () {
      final json = jsonDecode(
        PoseRecording.encode(SynthSet.reps(1).frames()),
      ) as Map<String, Object?>;
      expect(json.keys.toSet(), {'version', 'aspect', 'frames'});
      final frame = (json['frames']! as List<Object?>).first! as Map;
      expect(frame.keys.toSet(), {'t', 'j'});
    });

    test('anything that is not a recording gives no frames', () {
      for (final bad in [
        '',
        'not json',
        '[]',
        'null',
        '42',
        '{}',
        '{"version": 2, "frames": []}',
        '{"version": 1, "frames": "nope"}',
        '{"version": "1", "frames": []}',
        '<script>alert(1)</script>',
        "{'version': 1}",
      ]) {
        expect(PoseRecording.decode(bad), isEmpty, reason: bad);
      }
    });

    test('bad frames and joints are skipped, never thrown', () {
      const json = '''
{"version": 1, "aspect": "wide", "frames": [
  {"t": 0, "j": {"nose": [0.5, 0.5, 0.9], "tail": [1, 1, 1]}},
  {"t": -5, "j": {}},
  {"t": "10", "j": {}},
  {"t": 1e300, "j": {}},
  "frame",
  null,
  {"t": 66, "j": {"nose": [0.5, 0.5], "leftShoulder": ["a", 0, 1]}},
  {"t": 66, "j": {"nose": [0.5, 0.5, 0.9]}},
  {"t": 33, "j": {"nose": [0.5, 0.5, 0.9]}},
  {"t": 132, "j": {"nose": [1e12, 0.5, 0.9], "leftHip": [0.2, 0.3, 7]}},
  {"t": 198, "j": "nope"},
  {"t": 264}
]}''';
      final frames = PoseRecording.decode(json);
      expect(frames.map((f) => f.at.inMilliseconds), [0, 66, 132, 198, 264]);
      expect(frames.first.joints.keys, [PoseJoint.nose]);
      expect(frames.first.aspect, PoseFrame.defaultAspect);
      expect(frames[1].joints, isEmpty);
      expect(frames[2].joints, isEmpty);
    });

    test('a huge recording is cut at the limit', () {
      final big = jsonEncode({
        'version': 1,
        'frames': [
          for (var i = 0; i < PoseRecording.maxFrames + 50; i++)
            {'t': i, 'j': <String, Object?>{}},
        ],
      });
      expect(PoseRecording.decode(big), hasLength(PoseRecording.maxFrames));
    });
  });

  group('RecordedPoseSource', () {
    test('plays the frames in order, then stops on stop()', () async {
      final frames = SynthSet.reps(1).frames();
      final source = RecordedPoseSource(frames, realTime: false);
      final got = <PoseFrame>[];
      final sub = source.frames.listen(got.add);
      await source.start();
      expect(source.currentStatus.state, PoseSourceState.running);
      await pumpEventQueue();
      expect(got, hasLength(frames.length));
      await source.stop();
      expect(source.currentStatus, PoseSourceStatus.idle);
      await sub.cancel();
    });

    test('looping keeps time moving forward', () async {
      final frames = SynthSet.reps(1, fps: 5).frames();
      final source = RecordedPoseSource(frames, realTime: false, loop: true);
      final got = <PoseFrame>[];
      final sub = source.frames.listen((f) {
        got.add(f);
        if (got.length == frames.length * 2 + 1) unawaited(source.stop());
      });
      await source.start();
      await pumpEventQueue(times: 50);
      await sub.cancel();
      for (var i = 1; i < got.length; i++) {
        expect(got[i].at, greaterThan(got[i - 1].at));
      }
    });

    test('an empty recording does nothing and does not spin', () async {
      final source = RecordedPoseSource(const [], realTime: false, loop: true);
      await source.start();
      await pumpEventQueue();
      await source.stop();
    });
  });
}
