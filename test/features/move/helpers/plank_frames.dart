import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';

import 'synthetic_pose.dart';

/// A plank in segments: each is held for its duration with its sag (0 = a
/// straight body; 0.1 and more = hips clearly sagging), one after the other
/// on one timeline starting at [start].
List<PoseFrame> plankFrames(
  List<(Duration, double)> segments, {
  Duration start = Duration.zero,
  SynthView view = SynthView.sideLeft,
  double fps = 15,
}) {
  final out = <PoseFrame>[];
  var offset = start;
  for (final (length, sag) in segments) {
    final frames = SynthSet(
      view: view,
      lead: length,
      tail: Duration.zero,
      sag: sag,
      fps: fps,
    ).frames();
    for (final f in frames) {
      // The next segment's first frame is this one's last: no duplicate.
      if (f.at >= length && segments.last.$1 != length) continue;
      out.add(PoseFrame(at: offset + f.at, joints: f.joints, aspect: f.aspect));
    }
    offset += length;
  }
  return out;
}
