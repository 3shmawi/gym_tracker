import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';

/// Draws a pose frame as a **body**, not a stick figure: limbs, torso,
/// neck and head as outlined rounded shapes, in the line-drawing style of
/// the exercise pictures, with small dots on the joints the model saw.
/// The side further from the camera is drawn first and dimmer. Used where
/// there is no camera image (the iOS Simulator demo, the diagnostic
/// screen); with a camera, only the dots go over the real picture.
///
/// Sizes follow the body (torso length), so a near or far member looks the
/// same. Joints the model is unsure of are left out, never guessed.
class PoseBodyPainter extends CustomPainter {
  new({
    required this.frame,
    required this.outline,
    required this.fill,
    required this.farFill,
    required this.dot,
    this.minLikelihood = 0.5,
    this.drawBody = true,
  });

  final PoseFrame? frame;
  final Color outline;
  final Color fill;

  /// The far arm and leg.
  final Color farFill;
  final Color dot;
  final double minLikelihood;

  /// False over the live camera picture: the member is already in it, so
  /// only thin lines and the dots are drawn.
  final bool drawBody;

  @override
  void paint(Canvas canvas, Size size) {
    final f = frame;
    if (f == null || size.isEmpty) return;
    Offset? p(PoseJoint j) {
      final l = f.seen(j, minLikelihood: minLikelihood);
      return l == null ? null : Offset(l.x * size.width, l.y * size.height);
    }

    final ls = p(PoseJoint.leftShoulder);
    final rs = p(PoseJoint.rightShoulder);
    final lh = p(PoseJoint.leftHip);
    final rh = p(PoseJoint.rightHip);
    final shoulder = _mid(ls, rs);
    final hip = _mid(lh, rh);
    final unit = switch ((shoulder, hip, ls, rs)) {
      (final s?, final h?, _, _) when (s - h).distance > 1 => (s - h).distance,
      (_, _, final a?, final b?) when (a - b).distance > 1 =>
        (a - b).distance * 2,
      _ => size.shortestSide * 0.25,
    };

    // Near side: the one the model sees better.
    double side(List<PoseJoint> js) => js
        .map((j) => f.joints[j]?.likelihood ?? 0)
        .where((l) => l.isFinite)
        .fold(0, (a, b) => a + b);
    final leftScore = side(const [
      PoseJoint.leftShoulder,
      PoseJoint.leftElbow,
      PoseJoint.leftWrist,
      PoseJoint.leftHip,
    ]);
    final rightScore = side(const [
      PoseJoint.rightShoulder,
      PoseJoint.rightElbow,
      PoseJoint.rightWrist,
      PoseJoint.rightHip,
    ]);
    final leftNear = leftScore >= rightScore;
    // Seen from the side, one side is hidden: draw it dimmer, behind. Seen
    // from the front both are equally near: same fill for both.
    final oneSideHidden = (leftScore - rightScore).abs() > 1;

    void limbs({required bool left, required Color color}) {
      final s = left ? ls : rs;
      final e = p(left ? PoseJoint.leftElbow : PoseJoint.rightElbow);
      final w = p(left ? PoseJoint.leftWrist : PoseJoint.rightWrist);
      final h = left ? lh : rh;
      final k = p(left ? PoseJoint.leftKnee : PoseJoint.rightKnee);
      final a = p(left ? PoseJoint.leftAnkle : PoseJoint.rightAnkle);
      _capsule(canvas, h, k, unit * 0.26, color);
      _capsule(canvas, k, a, unit * 0.19, color);
      _foot(canvas, a, k, unit, color);
      _capsule(canvas, s, e, unit * 0.18, color);
      _capsule(canvas, e, w, unit * 0.15, color);
      _hand(canvas, w, e, unit, color);
    }

    if (!drawBody) {
      final line = Paint()
        ..color = dot
        ..strokeWidth = math.max(1.5, unit * 0.025)
        ..strokeCap = StrokeCap.round;
      for (final (a, b) in _bones) {
        final pa = p(a);
        final pb = p(b);
        if (pa != null && pb != null) canvas.drawLine(pa, pb, line);
      }
      _dots(canvas, p, unit);
      return;
    }
    limbs(left: !leftNear, color: oneSideHidden ? farFill : fill);
    _capsule(canvas, shoulder, hip, unit * 0.46, fill);
    // The shoulders as one piece (from the front the torso is hidden).
    _capsule(canvas, ls, rs, unit * 0.3, fill);
    final nose = p(PoseJoint.nose);
    if (shoulder != null && nose != null) {
      final neckEnd = Offset.lerp(shoulder, nose, 0.55)!;
      _capsule(canvas, shoulder, neckEnd, unit * 0.16, fill);
      _circle(canvas, Offset.lerp(shoulder, nose, 0.8)!, unit * 0.2, fill);
    }
    limbs(left: leftNear, color: fill);

    _dots(canvas, p, unit);
  }

  static const List<(PoseJoint, PoseJoint)> _bones = [
    (PoseJoint.nose, PoseJoint.leftShoulder),
    (PoseJoint.nose, PoseJoint.rightShoulder),
    (PoseJoint.leftShoulder, PoseJoint.rightShoulder),
    (PoseJoint.leftShoulder, PoseJoint.leftElbow),
    (PoseJoint.leftElbow, PoseJoint.leftWrist),
    (PoseJoint.rightShoulder, PoseJoint.rightElbow),
    (PoseJoint.rightElbow, PoseJoint.rightWrist),
    (PoseJoint.leftShoulder, PoseJoint.leftHip),
    (PoseJoint.rightShoulder, PoseJoint.rightHip),
    (PoseJoint.leftHip, PoseJoint.rightHip),
    (PoseJoint.leftHip, PoseJoint.leftKnee),
    (PoseJoint.leftKnee, PoseJoint.leftAnkle),
    (PoseJoint.rightHip, PoseJoint.rightKnee),
    (PoseJoint.rightKnee, PoseJoint.rightAnkle),
  ];

  void _dots(Canvas canvas, Offset? Function(PoseJoint) p, double unit) {
    final dots = Paint()..color = dot;
    final ring = Paint()
      ..color = fill
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1, unit * 0.025);
    for (final j in PoseJoint.values) {
      final at = p(j);
      if (at == null) continue;
      final r = math.max(2.5, unit * 0.045);
      canvas
        ..drawCircle(at, r, dots)
        ..drawCircle(at, r, ring);
    }
  }

  Offset? _mid(Offset? a, Offset? b) => switch ((a, b)) {
    (final a?, final b?) => Offset.lerp(a, b, 0.5),
    (final a?, null) => a,
    (null, final b?) => b,
    _ => null,
  };

  /// A rounded limb: a thick line in the outline colour, then a thinner one
  /// in the fill, so it reads as an outlined shape.
  void _capsule(Canvas c, Offset? a, Offset? b, double width, Color color) {
    if (a == null || b == null || !width.isFinite || width <= 0) return;
    final edge = math.max(1.5, width * 0.12);
    c
      ..drawLine(
        a,
        b,
        Paint()
          ..color = outline
          ..strokeWidth = width + edge * 2
          ..strokeCap = StrokeCap.round,
      )
      ..drawLine(
        a,
        b,
        Paint()
          ..color = color
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round,
      );
  }

  void _circle(Canvas c, Offset at, double r, Color color) {
    if (!r.isFinite || r <= 0) return;
    c
      ..drawCircle(at, r, Paint()..color = color)
      ..drawCircle(
        at,
        r,
        Paint()
          ..color = outline
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, r * 0.14),
      );
  }

  /// A hand: a short rounded shape past the wrist, along the forearm.
  void _hand(Canvas c, Offset? wrist, Offset? elbow, double unit, Color color) {
    if (wrist == null || elbow == null) return;
    final dir = wrist - elbow;
    if (dir.distance < 1) return;
    final tip = wrist + dir / dir.distance * unit * 0.12;
    _capsule(c, wrist, tip, unit * 0.13, color);
  }

  /// A foot: short, from the ankle away from the knee's side, on the floor.
  void _foot(Canvas c, Offset? ankle, Offset? knee, double unit, Color color) {
    if (ankle == null || knee == null) return;
    final shin = ankle - knee;
    if (shin.distance < 1) return;
    final along = shin / shin.distance;
    final toe = ankle + Offset(along.dx * 0.5, 1) * unit * 0.14;
    _capsule(c, ankle, toe, unit * 0.12, color);
  }

  @override
  bool shouldRepaint(PoseBodyPainter old) =>
      old.frame != frame ||
      old.outline != outline ||
      old.fill != fill ||
      old.farFill != farFill ||
      old.dot != dot;
}
