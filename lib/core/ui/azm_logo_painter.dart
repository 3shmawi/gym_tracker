import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

part 'azm_level_painter.dart';

/// Paints one frame of the approved Azm logo animation.
///
/// A 1:1 port of `docs/design/motion/splash_animation.dc.html`: the same SVG
/// shapes in the 100-unit box, the same gradients (objectBoundingBox) and
/// the same CSS keyframes, timing functions, `transform-box: fill-box` and
/// transform origins. Only the wordmark is left out (a canvas preview only).
///
/// [progress] runs 0 → 1 over the animation; 1 is the static logo.
class AzmLogoPainter extends CustomPainter {
  const new(this.progress, {this.light = false});

  final double progress;

  /// On a light background: the white glass edges are drawn dark instead
  /// (the only change), so the figures stay visible with no backdrop.
  final bool light;

  /// Units across the painted square. The square is centred on the static
  /// logo's centre ([_centre]), so the end frame sits exactly where the
  /// native splash draws the mark; 112 units leave room for the bars that
  /// step aside mid-animation.
  static const viewUnits = 112.0;
  static const _centre = Offset(48.5, 50);

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.clamp(0.0, 1.0);
    final unit = size.shortestSide / viewUnits;
    canvas
      ..save()
      ..translate(size.width / 2, size.height / 2)
      ..scale(unit)
      ..translate(-_centre.dx, -_centre.dy);
    _paintFigure1(canvas, t);
    _paintMiddle(canvas, t);
    _paintGreenBar(canvas, t);
    _paintFigure3(canvas, t);
    canvas.restore();
  }

  @override
  bool shouldRepaint(AzmLogoPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.light != light;

  // ── Figure 1: light lift ──────────────────────────────────────────────

  void _paintFigure1(Canvas canvas, double t) {
    canvas
      ..save()
      ..translate(_Motion.sideL.at(t), 0);
    _layer(canvas, _Motion.f1loadOpacity.at(t), () {
      canvas
        ..save()
        ..translate(0, _Motion.f1loadY.at(t));
      _Shapes.f1load.paint(canvas, light: light);
      canvas.restore();
    });
    _layer(canvas, _Motion.f1loadOpacity.at(t), () {
      _scaled(
        canvas,
        _Shapes.f1arms,
        const Offset(.5, 1),
        1,
        _Motion.f1armsScale.at(t),
      );
    });
    _Shapes.f1body.paint(canvas, light: light);
    canvas.restore();
  }

  // ── Figure 2: heavy lift, inside the middle bar ───────────────────────

  void _paintMiddle(Canvas canvas, double t) {
    canvas
      ..save()
      ..translate(_Motion.midL.at(t), 0);
    _layer(
      canvas,
      _Motion.b2fade.at(t),
      () => _Shapes.midBar.paint(canvas, light: light),
    );
    _layer(canvas, _Motion.f2appear.at(t), () {
      canvas
        ..save()
        ..translate(_Motion.f2barX.at(t), _Motion.f2barY.at(t));
      _Shapes.f2bar.paint(canvas, light: light);
      canvas.restore();
      _Shapes.f2body.paint(canvas, light: light);
      _scaled(
        canvas,
        _Shapes.f2arms,
        const Offset(.5, 1),
        1,
        _Motion.f2armsScale.at(t),
      );
    });
    canvas.restore();
  }

  // ── The green bar, which becomes figure 3 ─────────────────────────────

  void _paintGreenBar(Canvas canvas, double t) {
    canvas
      ..save()
      ..translate(_Motion.sideR.at(t), 0);
    _layer(
      canvas,
      _Motion.b3fade.at(t),
      () => _Shapes.greenBar.paint(canvas, light: light),
    );
    canvas.restore();
  }

  void _paintFigure3(Canvas canvas, double t) {
    _layer(canvas, _Motion.f3appear.at(t), () {
      canvas
        ..save()
        ..translate(55, 23.2)
        ..scale(.8);
      final grow = _Shapes.f3all.bounds;
      final origin = Offset(grow.center.dx, grow.bottom);
      canvas
        ..translate(origin.dx, origin.dy)
        ..scale(_Motion.f3growX.at(t), _Motion.f3growY.at(t))
        ..translate(-origin.dx, -origin.dy);
      _Shapes.f3body.paint(canvas, light: light);
      final pump = _Motion.pump.at(t);
      _scaled(canvas, _Shapes.pumpL, const Offset(.95, .6), pump, pump);
      _scaled(canvas, _Shapes.pumpR, const Offset(.05, .6), pump, pump);
      canvas.restore();
    });
  }

  /// CSS `scale()` with `transform-box: fill-box` and a % origin.
  void _scaled(
    Canvas canvas,
    _Group group,
    Offset origin,
    double sx,
    double sy,
  ) {
    final box = group.bounds;
    final o = Offset(
      box.left + box.width * origin.dx,
      box.top + box.height * origin.dy,
    );
    canvas
      ..save()
      ..translate(o.dx, o.dy)
      ..scale(sx, sy)
      ..translate(-o.dx, -o.dy);
    group.paint(canvas, light: light);
    canvas.restore();
  }

  /// SVG group opacity: the group is composited as one layer.
  static void _layer(Canvas canvas, double opacity, void Function() draw) {
    if (opacity <= 0) return;
    if (opacity >= 1) {
      draw();
      return;
    }
    canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, opacity));
    draw();
    canvas.restore();
  }
}

// ── Keyframes (the CSS @keyframes, offsets as fractions) ────────────────

/// CSS `cubic-bezier(.2,.8,.2,1)`.
const _easeOutBack = Cubic(.2, .8, .2, 1);

/// CSS `cubic-bezier(.4,0,.2,1)`.
const _standard = Cubic(.4, 0, .2, 1);

/// CSS `cubic-bezier(.2,.9,.3,1.2)` (a small overshoot).
const _grow = Cubic(.2, .9, .3, 1.2);

/// CSS `ease`, the default timing function.
const _ease = Cubic(.25, .1, .25, 1);

abstract final class _Motion {
  static const f1loadY = _Track([
    (0, 14),
    (.18, 0),
    (.24, 10),
    (.90, -6),
    (.97, 0),
    (1, 0),
  ], _easeOutBack);
  static const f1loadOpacity = _Track([
    (0, 1),
    (.18, 1),
    (.24, 0),
    (.90, 0),
    (.97, 1),
    (1, 1),
  ], _easeOutBack);
  static const f1armsScale = _Track([
    (0, .3),
    (.18, 1),
    (.24, .3),
    (.90, .3),
    (.97, 1),
    (1, 1),
  ], _easeOutBack);
  static const sideL = _Track([
    (0, 0),
    (.26, 0),
    (.32, -4.5),
    (.58, -4.5),
    (.62, 0),
    (.66, -2.6),
    (.87, -2.6),
    (.93, 0),
    (1, 0),
  ], _standard);
  static const sideR = _Track([
    (0, 0),
    (.26, 0),
    (.32, 16),
    (.58, 16),
    (.64, 0),
    (1, 0),
  ], _standard);
  static const f2appear = _Track([
    (0, 0),
    (.27, 0),
    (.32, 1),
    (.53, 1),
    (.58, 0),
    (1, 0),
  ], _ease);
  static const f2barX = _Track([
    (0, 0),
    (.32, 0),
    (.48, 0),
    (.50, .8),
    (.52, -.8),
    (.54, 0),
    (.60, 0),
    (1, 0),
  ], _ease);
  static const f2barY = _Track([
    (0, 16),
    (.32, 16),
    (.48, 0),
    (.50, 0),
    (.52, 0),
    (.54, 0),
    (.60, 14),
    (1, 14),
  ], _ease);
  static const f2armsScale = _Track([
    (0, .3),
    (.32, .3),
    (.48, 1),
    (.54, 1),
    (.60, .3),
    (1, .3),
  ], _ease);
  static const f3appear = _Track([
    (0, 0),
    (.64, 0),
    (.69, 1),
    (.87, 1),
    (.92, 0),
    (1, 0),
  ], _ease);
  static const f3growX = _Track([
    (0, .35),
    (.64, .35),
    (.71, 1),
    (1, 1),
  ], _grow);
  static const f3growY = _Track([(0, .9), (.64, .9), (.71, 1), (1, 1)], _grow);
  static const b2fade = _Track([
    (0, 1),
    (.27, 1),
    (.32, 0),
    (.53, 0),
    (.58, 1),
    (1, 1),
  ], _ease);
  static const b3fade = _Track([
    (0, 1),
    (.64, 1),
    (.69, 0),
    (.87, 0),
    (.92, 1),
    (1, 1),
  ], _ease);
  static const midL = _Track([
    (0, 0),
    (.62, 0),
    (.66, -14.1),
    (.87, -14.1),
    (.93, 0),
    (1, 0),
  ], _standard);
  static const pump = _Track([
    (0, 1),
    (.71, 1),
    (.75, 1.12),
    (.79, 1.02),
    (.83, 1.1),
    (.87, 1),
    (1, 1),
  ], _ease);
}

/// One animated value: CSS keyframes, with the timing function applied to
/// each interval between two keyframes (as CSS does).
class _Track {
  const new(this.keys, this.curve);

  final List<(double, double)> keys;
  final Curve curve;

  double at(double t) {
    if (t <= keys.first.$1) return keys.first.$2;
    for (var i = 0; i < keys.length - 1; i++) {
      final (t0, v0) = keys[i];
      final (t1, v1) = keys[i + 1];
      if (t <= t1) {
        if (t1 <= t0) return v1;
        return v0 + (v1 - v0) * curve.transform((t - t0) / (t1 - t0));
      }
    }
    return keys.last.$2;
  }
}

// ── Paints (the SVG <defs>) ─────────────────────────────────────────────

const _white = Color(0xFFFFFFFF);

/// The dark text colour (#0C1610), for lines on light backgrounds.
const _darkInk = Color(0xFF0C1610);

/// An SVG linearGradient in objectBoundingBox units.
enum _Grad {
  glass(
    Offset.zero,
    Offset(.4, 1),
    [
      Color.fromRGBO(255, 255, 255, .6),
      Color.fromRGBO(255, 255, 255, .2),
      Color.fromRGBO(255, 255, 255, .1),
    ],
    [0, .5, 1],
  ),
  edge(
    Offset.zero,
    Offset(1, 1),
    [
      Color.fromRGBO(255, 255, 255, .95),
      Color.fromRGBO(255, 255, 255, .15),
      Color.fromRGBO(255, 255, 255, .55),
    ],
    [0, .5, 1],
  ),

  /// [glass] strokes (the arms) for light backgrounds.
  glassLight(
    Offset.zero,
    Offset(.4, 1),
    [
      Color.fromRGBO(0x0C, 0x16, 0x10, .4),
      Color.fromRGBO(0x0C, 0x16, 0x10, .25),
      Color.fromRGBO(0x0C, 0x16, 0x10, .18),
    ],
    [0, .5, 1],
  ),

  /// [edge] for light backgrounds: the same stops in the dark text colour
  /// (#0C1610), lighter so it reads as an outline.
  edgeLight(
    Offset.zero,
    Offset(1, 1),
    [
      Color.fromRGBO(0x0C, 0x16, 0x10, .55),
      Color.fromRGBO(0x0C, 0x16, 0x10, .2),
      Color.fromRGBO(0x0C, 0x16, 0x10, .4),
    ],
    [0, .5, 1],
  ),
  greenGlass(
    Offset.zero,
    Offset(.3, 1),
    [
      Color.fromRGBO(0x86, 0xEF, 0xAC, .95),
      Color.fromRGBO(0x22, 0xC5, 0x5E, .85),
      Color.fromRGBO(0x15, 0x80, 0x3D, .9),
    ],
    [0, .55, 1],
  ),
  shine(
    Offset.zero,
    Offset(0, 1),
    [Color.fromRGBO(255, 255, 255, .35), Color.fromRGBO(255, 255, 255, 0)],
    [0, 1],
  );

  new(this.from, this.to, this.colors, this.stops);

  final Offset from;
  final Offset to;
  final List<Color> colors;
  final List<double> stops;

  Shader shader(Rect box) {
    final m = Matrix4.identity()
      ..translateByDouble(box.left, box.top, 0, 1)
      ..scaleByDouble(box.width, box.height, 1, 1);
    return ui.Gradient.linear(
      from,
      to,
      colors,
      stops,
      TileMode.clamp,
      m.storage,
    );
  }
}

/// A fill or stroke: a gradient or a flat colour.
class _Ink {
  const new({this.grad, this.color});

  final _Grad? grad;
  final Color? color;

  /// On a light background ([light]) every white line is drawn in the dark
  /// text colour instead: the glass edges, the arms (glass strokes) and
  /// the muscle details. White glass fills stay, now outlined.
  void apply(Paint paint, Rect box, {required bool light}) {
    final stroke = paint.style == PaintingStyle.stroke;
    if (grad != null) {
      final g = !light
          ? grad!
          : grad == _Grad.edge
          ? _Grad.edgeLight
          : grad == _Grad.glass && stroke
          ? _Grad.glassLight
          : grad!;
      paint.shader = g.shader(box);
    } else {
      final c = color!;
      paint.color = light && c.r == 1 && c.g == 1 && c.b == 1
          ? _darkInk.withValues(alpha: c.a)
          : c;
    }
  }
}

const _glass = _Ink(grad: _Grad.glass);
const _edge = _Ink(grad: _Grad.edge);
const _green = _Ink(grad: _Grad.greenGlass);
const _shine = _Ink(grad: _Grad.shine);
_Ink _whiteAt(double opacity) => _Ink(color: _white.withValues(alpha: opacity));

// ── Shapes (the SVG elements) ───────────────────────────────────────────

class _Shape {
  new(
    this.path, {
    this.fill,
    this.stroke,
    this.strokeWidth = 0,
    this.cap = StrokeCap.butt,
    this.join = StrokeJoin.miter,
  }) : bounds = _tightBounds(path);

  factory rect(
    double x,
    double y,
    double w,
    double h,
    double rx, {
    _Ink? fill,
    _Ink? stroke,
    double strokeWidth = 0,
  }) {
    final r = math.min(rx, math.min(w, h) / 2);
    return _Shape(
      Path()..addRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r)),
      ),
      fill: fill,
      stroke: stroke,
      strokeWidth: strokeWidth,
    );
  }

  factory circle(
    double cx,
    double cy,
    double r, {
    _Ink? fill,
    _Ink? stroke,
    double strokeWidth = 0,
  }) => _Shape(
    Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
    fill: fill,
    stroke: stroke,
    strokeWidth: strokeWidth,
  );

  factory path(
    String d, {
    _Ink? fill,
    _Ink? stroke,
    double strokeWidth = 0,
    StrokeCap cap = StrokeCap.butt,
    StrokeJoin join = StrokeJoin.miter,
  }) => _Shape(
    _parseSvgPath(d),
    fill: fill,
    stroke: stroke,
    strokeWidth: strokeWidth,
    cap: cap,
    join: join,
  );

  final Path path;
  final _Ink? fill;
  final _Ink? stroke;
  final double strokeWidth;
  final StrokeCap cap;
  final StrokeJoin join;

  /// The geometry's box (SVG `fill-box`, no stroke): what gradients and
  /// transform origins are relative to.
  final Rect bounds;

  void paint(Canvas canvas, {required bool light}) {
    if (fill != null) {
      final p = Paint()..isAntiAlias = true;
      fill!.apply(p, bounds, light: light);
      canvas.drawPath(path, p);
    }
    if (stroke != null) {
      final p = Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = cap
        ..strokeJoin = join;
      stroke!.apply(p, bounds, light: light);
      canvas.drawPath(path, p);
    }
  }
}

class _Group {
  new(this.shapes)
    : bounds = shapes
          .map((s) => s.bounds)
          .reduce((a, b) => a.expandToInclude(b));

  final List<_Shape> shapes;
  final Rect bounds;

  void paint(Canvas canvas, {required bool light}) {
    for (final s in shapes) {
      s.paint(canvas, light: light);
    }
  }
}

abstract final class _Shapes {
  static final f1load = _Group([
    _Shape.rect(13, 36, 33, 3.4, 1.7, fill: _green),
    _Shape.rect(
      11,
      31,
      4.5,
      13.5,
      1.6,
      fill: _green,
      stroke: _edge,
      strokeWidth: .6,
    ),
    _Shape.rect(
      43.5,
      31,
      4.5,
      13.5,
      1.6,
      fill: _green,
      stroke: _edge,
      strokeWidth: .6,
    ),
  ]);

  static final f1arms = _Group([
    _Shape.path(
      'M23.5 57 L19.5 38.5 M35.5 57 L39.5 38.5',
      stroke: _glass,
      strokeWidth: 4.2,
      cap: StrokeCap.round,
    ),
  ]);

  static final f1body = _Group([
    _Shape.circle(29.5, 47.5, 5, fill: _glass, stroke: _edge, strokeWidth: .8),
    _Shape.rect(
      22.5,
      54.5,
      14,
      23.5,
      7,
      fill: _glass,
      stroke: _edge,
      strokeWidth: 1,
    ),
  ]);

  static final midBar = _Group([
    _Shape.rect(53, 40, 14, 38, 7, fill: _glass, stroke: _edge, strokeWidth: 1),
  ]);

  static final f2bar = _Group([
    _Shape.rect(45, 20, 30, 4, 2, fill: _green),
    for (final (x, y, w, h) in const [
      (42.0, 12.0, 6.0, 20.0),
      (37.0, 14.5, 4.5, 15.0),
      (72.0, 12.0, 6.0, 20.0),
      (78.5, 14.5, 4.5, 15.0),
    ])
      _Shape.rect(x, y, w, h, 2, fill: _green, stroke: _edge, strokeWidth: .6),
  ]);

  static final f2body = _Group([
    _Shape.path(
      'M55.4 65.5 L55 76.6 Q55 78.2 56.6 78.2 L58.4 78.2 Q59.3 78.2 59.3 77.1 '
      'L59.5 66.2 Z M64.6 65.5 L65 76.6 Q65 78.2 63.4 78.2 L61.6 78.2 '
      'Q60.7 78.2 60.7 77.1 L60.5 66.2 Z',
      fill: _glass,
      stroke: _edge,
      strokeWidth: .7,
    ),
    _Shape.path(
      'M51 42 Q60 38.8 69 42 Q67.2 50 65.8 58 L65.8 64.5 Q65.8 67 63.3 67 '
      'L56.7 67 Q54.2 67 54.2 64.5 L54.2 58 Q52.8 50 51 42 Z',
      fill: _glass,
      stroke: _edge,
      strokeWidth: .9,
    ),
    _Shape.path(
      'M56.6 37.8 L63.4 37.8 L68 41.6 Q60 39.4 52 41.6 Z',
      fill: _glass,
      stroke: _edge,
      strokeWidth: .6,
    ),
    _Shape.path(
      'M54.6 46.6 Q57.4 49 60 47.8 Q62.6 49 65.4 46.6',
      stroke: _whiteAt(.45),
      strokeWidth: .7,
      cap: StrokeCap.round,
    ),
    _Shape.path(
      'M60 50.2 L60 60 M58 53.4 L62 53.4 M58.2 56.6 L61.8 56.6',
      stroke: _whiteAt(.25),
      strokeWidth: .6,
      cap: StrokeCap.round,
    ),
    _Shape.circle(60, 33.4, 4.6, fill: _glass, stroke: _edge, strokeWidth: .8),
  ]);

  static final f2arms = _Group([
    _Shape.path(
      'M54.8 40.6 C53.4 36.6 49 36.4 48.4 38.6 C47 36.6 45.4 34 45.4 31.2 '
      'C45.4 29.6 46.2 28.6 47.2 28.2 L47.9 23.4 L51.6 23 C51.4 26 51 28.4 '
      '50.6 30.2 C52.6 31.8 53.6 34.4 53.2 37.2 L54.6 44.2 Z',
      fill: _glass,
      stroke: _edge,
      strokeWidth: .8,
      join: StrokeJoin.round,
    ),
    _Shape.path(
      'M53.6 39.6 Q51.2 37.8 49.2 39.2 M52.6 36.4 Q52 33.4 50.6 31.8',
      stroke: _whiteAt(.55),
      strokeWidth: .7,
      cap: StrokeCap.round,
    ),
    _Shape.path(
      'M47.2 27 Q48.4 25.6 49.4 24',
      stroke: _whiteAt(.28),
      strokeWidth: .6,
      cap: StrokeCap.round,
    ),
    _Shape.circle(
      49.7,
      22.2,
      2.8,
      fill: _glass,
      stroke: _edge,
      strokeWidth: .6,
    ),
    _Shape.path(
      'M 65.2 40.6 C 66.6 36.6 71 36.4 71.6 38.6 C 73 36.6 74.6 34 74.6 31.2 '
      'C 74.6 29.6 73.8 28.6 72.8 28.2 L 72.1 23.4 L 68.4 23 C 68.6 26 69 '
      '28.4 69.4 30.2 C 67.4 31.8 66.4 34.4 66.8 37.2 L 65.4 44.2 Z',
      fill: _glass,
      stroke: _edge,
      strokeWidth: .8,
      join: StrokeJoin.round,
    ),
    _Shape.path(
      'M 66.4 39.6 Q 68.8 37.8 70.8 39.2 M 67.4 36.4 Q 68 33.4 69.4 31.8',
      stroke: _whiteAt(.55),
      strokeWidth: .7,
      cap: StrokeCap.round,
    ),
    _Shape.path(
      'M 72.8 27 Q 71.6 25.6 70.6 24',
      stroke: _whiteAt(.28),
      strokeWidth: .6,
      cap: StrokeCap.round,
    ),
    _Shape.circle(
      70.3,
      22.2,
      2.8,
      fill: _glass,
      stroke: _edge,
      strokeWidth: .6,
    ),
  ]);

  static final greenBar = _Group([
    _Shape.rect(72, 22, 14, 56, 7, fill: _green, stroke: _edge, strokeWidth: 1),
    _Shape.rect(74, 24, 4.5, 22, 2.25, fill: _shine),
  ]);

  static final f3body = _Group([
    _Shape.path(
      'M24.6 54 L24 66.5 Q24 68.5 26 68.5 L28.4 68.5 Q29.4 68.5 29.4 67.2 '
      'L29.6 55 Z M35.4 54 L36 66.5 Q36 68.5 34 68.5 L31.6 68.5 Q30.6 68.5 '
      '30.6 67.2 L30.4 55 Z',
      fill: _glass,
      stroke: _edge,
      strokeWidth: .7,
    ),
    _Shape.path(
      'M17.5 22 Q30 17.5 42.5 22 Q40.5 30 37.6 40 Q36.2 45 36.6 49 L37 54 '
      'Q37 56.5 34.5 56.5 L25.5 56.5 Q23 56.5 23 54 L23.4 49 Q23.8 45 22.4 '
      '40 Q19.5 30 17.5 22 Z',
      fill: _green,
      stroke: _edge,
      strokeWidth: .9,
    ),
    _Shape.path(
      'M25.5 14.5 L34.5 14.5 L41.5 21.2 Q30 17.8 18.5 21.2 Z',
      fill: _glass,
      stroke: _edge,
      strokeWidth: .6,
    ),
    _Shape.path(
      'M22.6 27.5 Q26.2 31 30 29.4 Q33.8 31 37.4 27.5',
      stroke: _whiteAt(.5),
      strokeWidth: .8,
      cap: StrokeCap.round,
    ),
    _Shape.path(
      'M30 31.8 L30 47 M27 35.6 L33 35.6 M27.3 39.6 L32.7 39.6 M27.6 43.6 '
      'L32.4 43.6',
      stroke: _whiteAt(.3),
      strokeWidth: .7,
      cap: StrokeCap.round,
    ),
    _Shape.circle(30, 9, 4.8, fill: _glass, stroke: _edge, strokeWidth: .8),
  ]);

  static final pumpL = _Group([
    _Shape.path(
      'M19.6 18.4 C18 14.4 13.6 14.6 12.8 18.2 C12.9 13.4 11 12.2 10.3 15.8 '
      'L10.6 12.2 L5.4 12.6 C4.2 17 3.2 21.5 3.6 24.6 C4 27.6 7.2 28.4 10.5 '
      '27.8 C14 27.4 17 27.2 19.4 26.4 Z',
      fill: _glass,
      stroke: _edge,
      strokeWidth: .8,
      join: StrokeJoin.round,
    ),
    _Shape.path(
      'M18.6 18.8 Q16.6 15.8 13.6 18 M12.3 17.4 Q12 14.6 10.8 15.6',
      stroke: _whiteAt(.55),
      strokeWidth: .7,
      cap: StrokeCap.round,
    ),
    _Shape.path(
      'M8.2 23 Q6.4 19.4 7.6 14',
      stroke: _whiteAt(.28),
      strokeWidth: .6,
      cap: StrokeCap.round,
    ),
    _Shape.circle(8, 10.4, 3.9, fill: _green, stroke: _edge, strokeWidth: .6),
  ]);

  static final pumpR = _Group([
    _Shape.path(
      'M 40.4 18.4 C 42 14.4 46.4 14.6 47.2 18.2 C 47.1 13.4 49 12.2 49.7 '
      '15.8 L 49.4 12.2 L 54.6 12.6 C 55.8 17 56.8 21.5 56.4 24.6 C 56 27.6 '
      '52.8 28.4 49.5 27.8 C 46 27.4 43 27.2 40.6 26.4 Z',
      fill: _glass,
      stroke: _edge,
      strokeWidth: .8,
      join: StrokeJoin.round,
    ),
    _Shape.path(
      'M 41.4 18.8 Q 43.4 15.8 46.4 18 M 47.7 17.4 Q 48 14.6 49.2 15.6',
      stroke: _whiteAt(.55),
      strokeWidth: .7,
      cap: StrokeCap.round,
    ),
    _Shape.path(
      'M 51.8 23 Q 53.6 19.4 52.4 14',
      stroke: _whiteAt(.28),
      strokeWidth: .6,
      cap: StrokeCap.round,
    ),
    _Shape.circle(52, 10.4, 3.9, fill: _green, stroke: _edge, strokeWidth: .6),
  ]);

  /// Everything inside `.f3grow` (its fill-box is the scale origin).
  static final f3all = _Group([
    ...f3body.shapes,
    ...pumpL.shapes,
    ...pumpR.shapes,
  ]);
}

/// The SVG path commands the design uses: absolute M, L, Q, C and Z.
Path _parseSvgPath(String d) {
  final tokens = RegExp(r'[MLQCZ]|-?\d*\.?\d+')
      .allMatches(d)
      .map((m) => m.group(0)!)
      .toList();
  final path = Path();
  var i = 0;
  var command = '';
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if (RegExp('[MLQCZ]').hasMatch(tokens[i])) command = tokens[i++];
    switch (command) {
      case 'M':
        path.moveTo(next(), next());
        command = 'L'; // Extra pairs after M are line-tos.
      case 'L':
        path.lineTo(next(), next());
      case 'Q':
        path.quadraticBezierTo(next(), next(), next(), next());
      case 'C':
        path.cubicTo(next(), next(), next(), next(), next(), next());
      case 'Z':
        path.close();
      default:
        throw FormatException('Unsupported path command', d);
    }
  }
  return path;
}

/// The tight box of a path's geometry (curves sampled, not their control
/// points), like the browser's `getBBox()`.
Rect _tightBounds(Path path) {
  var left = double.infinity;
  var top = double.infinity;
  var right = double.negativeInfinity;
  var bottom = double.negativeInfinity;
  for (final metric in path.computeMetrics()) {
    const steps = 400;
    for (var s = 0; s <= steps; s++) {
      final p = metric.getTangentForOffset(metric.length * s / steps)!.position;
      left = math.min(left, p.dx);
      top = math.min(top, p.dy);
      right = math.max(right, p.dx);
      bottom = math.max(bottom, p.dy);
    }
  }
  return Rect.fromLTRB(left, top, right, bottom);
}
