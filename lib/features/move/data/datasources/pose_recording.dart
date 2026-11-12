import 'dart:convert';

import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';

/// Landmark recordings: joints and times only, never an image. Used for
/// test fixtures (made from the owner's own videos on their computer,
/// `tool/pose_record/`), the integration demo and the diagnostic screen.
///
/// ```json
/// {"version": 1, "aspect": 0.75,
///  "frames": [{"t": 0, "j": {"leftShoulder": [0.41, 0.52, 0.98], …}}]}
/// ```
/// `t` is milliseconds; each joint is `[x, y, likelihood]`.
abstract final class PoseRecording {
  static const version = 1;

  /// At most this many frames (about 33 minutes at 15 fps): a recording
  /// is a set, not a film.
  static const maxFrames = 30000;

  /// Frames from [json]. Anything malformed is skipped, never thrown: an
  /// unknown joint, a wrong type, a missing field, a frame out of order.
  /// A document that is not a recording at all gives no frames.
  static List<PoseFrame> decode(String json) {
    final Object? root;
    try {
      root = jsonDecode(json);
    } on FormatException {
      return const [];
    }
    if (root is! Map<String, Object?> || root['version'] != version) {
      return const [];
    }
    final aspect = switch (root['aspect']) {
      final num a => a.toDouble(),
      _ => PoseFrame.defaultAspect,
    };
    final list = root['frames'];
    if (list is! List<Object?>) return const [];
    final frames = <PoseFrame>[];
    Duration? last;
    for (final item in list.take(maxFrames)) {
      if (item is! Map<String, Object?>) continue;
      final t = item['t'];
      if (t is! num || !t.isFinite || t < 0 || t > 1e8) continue;
      final at = Duration(microseconds: (t * 1000).round());
      if (last != null && at <= last) continue;
      final joints = <PoseJoint, Landmark>{};
      if (item['j'] case final Map<String, Object?> j) {
        for (final joint in PoseJoint.values) {
          if (j[joint.name] case [final num x, final num y, final num l]) {
            final landmark = Landmark(
              x: x.toDouble(),
              y: y.toDouble(),
              likelihood: l.toDouble(),
            );
            if (landmark.isSane) joints[joint] = landmark;
          }
        }
      }
      frames.add(PoseFrame(at: at, joints: joints, aspect: aspect));
      last = at;
    }
    return frames;
  }

  static String encode(List<PoseFrame> frames) => jsonEncode({
    'version': version,
    'aspect': frames.isEmpty ? PoseFrame.defaultAspect : frames.first.aspect,
    'frames': [
      for (final f in frames)
        {
          't': f.at.inMicroseconds / 1000,
          'j': {
            for (final MapEntry(key: joint, value: l) in f.joints.entries)
              joint.name: [_round(l.x), _round(l.y), _round(l.likelihood)],
          },
        },
    ],
  });

  static double _round(double v) => (v * 10000).roundToDouble() / 10000;
}
