import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/move/domain/detectors/push_up_detector.dart';
import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:gym_tracker/features/move/domain/usecases/placement.dart';

import '../helpers/synthetic_pose.dart';

/// Runs frames through a detector and the tracker; the frame time when the
/// round would start, or null.
(Duration?, PlacementChecks) place(List<PoseFrame> frames) {
  final detector = PushUpDetector();
  final tracker = PlacementTracker();
  for (final f in frames) {
    if (tracker.update(detector.onFrame(f), f.at)) {
      return (f.at, tracker.checks);
    }
  }
  return (null, tracker.checks);
}

void main() {
  test('holding the plank in view starts the round by itself', () {
    for (final view in SynthView.values) {
      final (start, checks) = place(
        SynthSet(view: view, lead: const Duration(seconds: 6)).frames(),
      );
      expect(start, isNotNull, reason: view.name);
      // Found (0.5 s) + view (10 frames) + plank 1 s + all green 1 s.
      expect(start!.inMilliseconds, inInclusiveRange(2000, 4000));
      expect(checks.allGood, isTrue);
    }
  });

  test('nobody in the picture: nothing is green', () {
    final frames = [
      for (var i = 0; i < 100; i++)
        PoseFrame(
          at: Duration(milliseconds: i * 66),
          joints: const {},
        ),
    ];
    final (start, checks) = place(frames);
    expect(start, isNull);
    expect(checks, const PlacementChecks());
  });

  test('feet out of the picture: not in frame, so no start', () {
    final (start, checks) = place(
      const SynthSet(shiftX: 0.3, lead: Duration(seconds: 8)).frames(),
    );
    expect(start, isNull);
    expect(checks.bodyFound, isTrue);
    expect(checks.inFrame, isFalse);
  });

  test('a dark room: light stays red', () {
    final (start, checks) = place(
      const SynthSet(likelihood: 0.35, lead: Duration(seconds: 8)).frames(),
    );
    expect(start, isNull);
    expect(checks.light, isFalse);
  });

  test('moving the whole time: no plank, no start', () {
    final (start, _) = place(
      SynthSet.reps(4, rep: const RepSpec(restAfter: Duration.zero))
          .frames()
          .where((f) => f.at > const Duration(milliseconds: 1600))
          .toList(),
    );
    expect(start, isNull);
  });
}
