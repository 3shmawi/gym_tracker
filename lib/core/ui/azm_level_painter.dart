part of 'azm_logo_painter.dart';

/// The three level figures (`docs/design/motion/level_figures.dc.html`).
enum LevelFigure {
  /// `lv1`: a figure pressing a light bar.
  beginner,

  /// `lv2`: broader shoulders, pressing a heavy bar.
  intermediate,

  /// `lv3`: a bodybuilder in a double-biceps pose.
  pro,
}

/// Paints one level figure.
///
/// A 1:1 port of the `lv1`, `lv2` and `lv3` symbols: the same shapes in the
/// 60×70 box, the same gradients (objectBoundingBox) and paint order. `lv2`
/// and `lv3` are the logo's heavy-lift and flex figures (the design reuses
/// them), so they are painted from the same shapes as [AzmLogoPainter].
///
/// The box is fitted into the canvas and centred (SVG `xMidYMid meet`).
class AzmLevelPainter extends CustomPainter {
  const new(this.figure, {this.light = false});

  final LevelFigure figure;

  /// On a light background: the white glass edges, arms and muscle details
  /// are drawn dark, as in [AzmLogoPainter.light].
  final bool light;

  /// The symbols' viewBox.
  static const viewBox = Size(60, 70);

  @override
  void paint(Canvas canvas, Size size) {
    final unit = math.min(
      size.width / viewBox.width,
      size.height / viewBox.height,
    );
    canvas
      ..save()
      ..translate(
        (size.width - viewBox.width * unit) / 2,
        (size.height - viewBox.height * unit) / 2,
      )
      ..scale(unit);
    switch (figure) {
      case LevelFigure.beginner:
        _LevelShapes.lv1.paint(canvas, light: light);
      case LevelFigure.intermediate:
        // `<g transform="translate(-30 -10)">` around the logo's figure 2.
        canvas.translate(-30, -10);
        _Shapes.f2bar.paint(canvas, light: light);
        _Shapes.f2body.paint(canvas, light: light);
        _Shapes.f2arms.paint(canvas, light: light);
      case LevelFigure.pro:
        _Shapes.f3body.paint(canvas, light: light);
        _Shapes.pumpL.paint(canvas, light: light);
        _Shapes.pumpR.paint(canvas, light: light);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(AzmLevelPainter oldDelegate) =>
      oldDelegate.figure != figure || oldDelegate.light != light;
}

abstract final class _LevelShapes {
  /// `lv1`: unlike the logo's figure 1, its plates have no edge stroke and
  /// it sits in the 60×70 box.
  static final lv1 = _Group([
    _Shape.rect(12, 20, 36, 3.4, 1.7, fill: _green),
    _Shape.rect(10, 15.5, 4.5, 12.5, 1.6, fill: _green),
    _Shape.rect(45.5, 15.5, 4.5, 12.5, 1.6, fill: _green),
    _Shape.path(
      'M24 42 L20 22.5 M36 42 L40 22.5',
      stroke: _glass,
      strokeWidth: 4.2,
      cap: StrokeCap.round,
    ),
    _Shape.circle(30, 32.5, 5, fill: _glass, stroke: _edge, strokeWidth: .8),
    _Shape.rect(
      23,
      39.5,
      14,
      24,
      7,
      fill: _glass,
      stroke: _edge,
      strokeWidth: 1,
    ),
  ]);
}
