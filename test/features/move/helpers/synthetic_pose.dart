import 'dart:math' as math;

import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';

/// Where the synthetic camera stands.
enum SynthView {
  /// On the floor at the member's side, head on the left of the picture.
  sideLeft,

  /// The same from the other side (head on the right).
  sideRight,

  /// On the floor in front of the head.
  front,
}

/// One rep: how deep (0..1 of a full push-up), how long top to top, and
/// the rest at the top after it.
class RepSpec {
  const new({
    this.depth = 1,
    this.duration = const Duration(milliseconds: 1600),
    this.bottomHold = Duration.zero,
    this.restAfter = const Duration(milliseconds: 400),
  });

  final double depth;
  final Duration duration;
  final Duration bottomHold;
  final Duration restAfter;
}

/// A synthetic push-up set: a stick figure drawn the way the pose model
/// reports a real person (same joints, likelihoods, hidden far side).
class SynthSet {
  const new({
    this.view = SynthView.sideLeft,
    this.reps = const [],
    this.fps = 15,
    this.scale = 1,
    this.lead = const Duration(milliseconds: 1500),
    this.tail = const Duration(milliseconds: 800),
    this.noise = 0,
    this.dropRate = 0,
    this.seed = 7,
    this.shiftX = 0,
    this.likelihood = 0.95,
    this.sag = 0,
    this.aspect = 0.75,
    this.gaps = const [],
    this.startAtBottom = false,
  });

  /// [count] identical reps.
  factory reps(
    int count, {
    SynthView view = SynthView.sideLeft,
    RepSpec rep = const RepSpec(),
    double fps = 15,
    double scale = 1,
    double noise = 0,
    double dropRate = 0,
    int seed = 7,
  }) => SynthSet(
    view: view,
    reps: List.filled(count, rep),
    fps: fps,
    scale: scale,
    noise: noise,
    dropRate: dropRate,
    seed: seed,
  );

  final SynthView view;
  final List<RepSpec> reps;
  final double fps;

  /// Body size: 1 = an adult filling the frame well; 0.6–1.4 in tests.
  final double scale;

  /// Holding the plank at the top before the first rep (the placement).
  final Duration lead;
  final Duration tail;

  /// Gaussian noise on every coordinate, in fractions of the image.
  final double noise;

  /// Fraction of frames the model never returns (dropped while busy).
  final double dropRate;
  final int seed;

  /// Moves the whole body sideways, in fractions of the image height.
  final double shiftX;

  /// Likelihood of the joints the camera sees well.
  final double likelihood;

  /// Hips lower than the shoulder–ankle line, in body lengths.
  final double sag;
  final double aspect;

  /// Time ranges in which the member is out of the picture (frames come
  /// with no joints).
  final List<(Duration, Duration)> gaps;

  /// The set starts in the bottom position (no plank first).
  final bool startAtBottom;

  /// The depth (0..1) at [t] from the start of the set.
  double depthAt(Duration t) {
    var cursor = lead;
    if (t < cursor) return startAtBottom ? 1 : 0;
    for (final rep in reps) {
      final moving = rep.duration - rep.bottomHold;
      final down = moving * 0.5;
      final end = cursor + rep.duration;
      if (t < end) {
        final into = t - cursor;
        if (into < down) return rep.depth * _ease(into, down);
        if (into < down + rep.bottomHold) return rep.depth;
        final up = into - down - rep.bottomHold;
        return rep.depth * (1 - _ease(up, moving - down));
      }
      cursor = end;
      if (t < cursor + rep.restAfter) return 0;
      cursor += rep.restAfter;
    }
    return 0;
  }

  Duration get length {
    var total = lead + tail;
    for (final r in reps) {
      total += r.duration + r.restAfter;
    }
    return total;
  }

  List<PoseFrame> frames() {
    final random = math.Random(seed);
    final step = Duration(microseconds: (1e6 / fps).round());
    final out = <PoseFrame>[];
    for (var t = Duration.zero; t <= length; t += step) {
      if (dropRate > 0 && random.nextDouble() < dropRate) continue;
      final hidden = gaps.any((g) => t >= g.$1 && t < g.$2);
      out.add(
        PoseFrame(
          at: t,
          aspect: aspect,
          joints: hidden ? const {} : _joints(depthAt(t), random),
        ),
      );
    }
    return out;
  }

  Map<PoseJoint, Landmark> _joints(double depth, math.Random random) {
    final world = view == SynthView.front
        ? _front(depth)
        : _side(depth, mirrored: view == SynthView.sideRight);
    return {
      for (final MapEntry(key: joint, value: (x, y, l)) in world.entries)
        joint: Landmark(
          x: (x + shiftX) / aspect + _gauss(random) * noise,
          y: y + _gauss(random) * noise,
          likelihood: l,
        ),
    };
  }

  /// Side view in image-height units: x across, y down, floor at 0.62.
  Map<PoseJoint, (double, double, double)> _side(
    double depth, {
    required bool mirrored,
  }) {
    const floor = 0.62;
    final s = scale;
    final upper = 0.11 * s;
    final fore = 0.10 * s;
    final bodyLength = 0.40 * s;
    final wristX = 0.10 + 0.06 * s;
    final elbowAngle = (172 - depth * 92) * math.pi / 180;
    final shoulderToWrist = math.sqrt(
      upper * upper + fore * fore - 2 * upper * fore * math.cos(elbowAngle),
    );
    final shoulder = (wristX, floor - shoulderToWrist);
    final wrist = (wristX, floor);
    final along =
        (fore * fore - upper * upper + shoulderToWrist * shoulderToWrist) /
        (2 * shoulderToWrist);
    final out = math.sqrt(math.max(0, fore * fore - along * along));
    final elbow = (wristX + out, floor - along);
    final ankleY = floor - 0.01 * s;
    final rise = ankleY - shoulder.$2;
    final run = math.sqrt(math.max(0, bodyLength * bodyLength - rise * rise));
    final ankle = (wristX + run, ankleY);
    (double, double) lerp((double, double) a, (double, double) b, double f) =>
        (a.$1 + (b.$1 - a.$1) * f, a.$2 + (b.$2 - a.$2) * f);
    final hipLine = lerp(shoulder, ankle, 0.45);
    final hip = (hipLine.$1, hipLine.$2 + sag * bodyLength);
    final knee = lerp(hip, ankle, 0.55);
    final dirX = (shoulder.$1 - ankle.$1) / bodyLength;
    final dirY = (shoulder.$2 - ankle.$2) / bodyLength;
    final nose = (
      shoulder.$1 + dirX * 0.07 * s,
      shoulder.$2 + dirY * 0.07 * s + 0.01 * s,
    );
    final width = aspect;
    (double, double) far((double, double) p) =>
        (p.$1 + 0.008 * s, p.$2 - 0.004 * s);
    (double, double) m((double, double) p) =>
        mirrored ? (width - p.$1, p.$2) : p;
    final l = likelihood;
    // The near side is the left one for sideLeft, the right one when
    // mirrored, so both arms' code paths are used.
    final near = <String, (double, double)>{
      'shoulder': shoulder,
      'elbow': elbow,
      'wrist': wrist,
      'hip': hip,
      'knee': knee,
      'ankle': ankle,
    };
    final nearIsLeft = !mirrored;
    PoseJoint j(String part, {required bool left}) => switch ((part, left)) {
      ('shoulder', true) => PoseJoint.leftShoulder,
      ('shoulder', false) => PoseJoint.rightShoulder,
      ('elbow', true) => PoseJoint.leftElbow,
      ('elbow', false) => PoseJoint.rightElbow,
      ('wrist', true) => PoseJoint.leftWrist,
      ('wrist', false) => PoseJoint.rightWrist,
      ('hip', true) => PoseJoint.leftHip,
      ('hip', false) => PoseJoint.rightHip,
      ('knee', true) => PoseJoint.leftKnee,
      ('knee', false) => PoseJoint.rightKnee,
      ('ankle', true) => PoseJoint.leftAnkle,
      _ => PoseJoint.rightAnkle,
    };
    double farLikelihood(String part) =>
        part == 'shoulder' || part == 'hip' ? l * 0.47 : l * 0.32;
    return {
      PoseJoint.nose: (m(nose).$1, m(nose).$2, l),
      for (final e in near.entries) ...{
        j(e.key, left: nearIsLeft): (m(e.value).$1, m(e.value).$2, l),
        j(e.key, left: !nearIsLeft): (
          m(far(e.value)).$1,
          m(far(e.value)).$2,
          farLikelihood(e.key),
        ),
      },
    };
  }

  /// Front view: the camera on the floor in front of the head.
  Map<PoseJoint, (double, double, double)> _front(double depth) {
    const floor = 0.80;
    final w = 0.16 * scale;
    final cx = aspect / 2;
    final h = 1.15 * (1 - 0.7 * depth);
    final sy = floor - h * w;
    final l = likelihood;
    (double, double, double) at(double x, double y, double lk) => (x, y, lk);
    final elbowOut = 0.05 * w + 0.35 * w * depth;
    final midY = (sy + floor) / 2;
    return {
      PoseJoint.nose: at(cx, sy - 0.1 * w, l),
      PoseJoint.leftShoulder: at(cx + w / 2, sy, l),
      PoseJoint.rightShoulder: at(cx - w / 2, sy, l),
      PoseJoint.leftElbow: at(cx + 0.55 * w + elbowOut, midY, l),
      PoseJoint.rightElbow: at(cx - 0.55 * w - elbowOut, midY, l),
      PoseJoint.leftWrist: at(cx + 0.6 * w, floor, l),
      PoseJoint.rightWrist: at(cx - 0.6 * w, floor, l),
      // Behind the shoulders, far away: the model barely sees them.
      PoseJoint.leftHip: at(cx + 0.35 * w, sy - 0.15 * w, 0.15),
      PoseJoint.rightHip: at(cx - 0.35 * w, sy - 0.15 * w, 0.15),
      PoseJoint.leftKnee: at(cx + 0.2 * w, floor - 0.1 * w, 0.1),
      PoseJoint.rightKnee: at(cx - 0.2 * w, floor - 0.1 * w, 0.1),
      PoseJoint.leftAnkle: at(cx + 0.1 * w, floor - 0.05 * w, 0.1),
      PoseJoint.rightAnkle: at(cx - 0.1 * w, floor - 0.05 * w, 0.1),
    };
  }

  static double _ease(Duration into, Duration over) {
    if (over <= Duration.zero) return 1;
    final f = (into.inMicroseconds / over.inMicroseconds).clamp(0.0, 1.0);
    return 0.5 - math.cos(f * math.pi) / 2;
  }

  static double _gauss(math.Random r) {
    final u1 = math.max(r.nextDouble(), 1e-12);
    final u2 = r.nextDouble();
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
  }
}
