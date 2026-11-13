import 'dart:math' as math;

import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';

/// A point in image-height units (x is scaled by the aspect ratio), so
/// distances and angles are true to the picture.
typedef Pt = ({double x, double y});

Pt ptOf(Landmark l, double aspect) => (x: l.x * aspect, y: l.y);

double distance(Pt a, Pt b) => math.sqrt(_sq(a.x - b.x) + _sq(a.y - b.y));

Pt midpoint(Pt a, Pt b) => (x: (a.x + b.x) / 2, y: (a.y + b.y) / 2);

/// The angle at [b] between [a] and [c], in degrees (0..180). Null when two
/// points coincide (no angle).
double? angleAt(Pt a, Pt b, Pt c) {
  final v1x = a.x - b.x;
  final v1y = a.y - b.y;
  final v2x = c.x - b.x;
  final v2y = c.y - b.y;
  final n1 = math.sqrt(_sq(v1x) + _sq(v1y));
  final n2 = math.sqrt(_sq(v2x) + _sq(v2y));
  if (n1 < 1e-6 || n2 < 1e-6) return null;
  final cos = ((v1x * v2x + v1y * v2y) / (n1 * n2)).clamp(-1.0, 1.0);
  return math.acos(cos) * 180 / math.pi;
}

double _sq(double v) => v * v;
