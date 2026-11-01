import 'package:flutter/widgets.dart';
import 'package:gym_tracker/core/ui/azm_logo_painter.dart';
import 'package:gym_tracker/l10n/l10n.dart';

export 'package:gym_tracker/core/ui/azm_logo_painter.dart' show LevelFigure;

/// A level figure (beginner / intermediate / pro) from the design, [width]
/// wide and 70/60 of that tall. Static, transparent background, never
/// mirrored in Arabic.
///
/// To the screen reader it is one image with the design's description
/// ([semanticsLabel] overrides it).
class AzmLevelFigure extends StatelessWidget {
  const new({
    required this.figure,
    required this.width,
    this.brightness = Brightness.dark,
    this.semanticsLabel,
    super.key,
  });

  final LevelFigure figure;
  final double width;

  /// The background it sits on. [Brightness.light] draws the white lines
  /// dark so the figure stays visible.
  final Brightness brightness;

  final String? semanticsLabel;

  /// Height for [width], from the 60×70 box.
  static double heightFor(double width) =>
      width * AzmLevelPainter.viewBox.height / AzmLevelPainter.viewBox.width;

  String _describe(BuildContext context) {
    final l10n = context.l10n;
    return switch (figure) {
      LevelFigure.beginner => l10n.levelFigureBeginner,
      LevelFigure.intermediate => l10n.levelFigureIntermediate,
      LevelFigure.pro => l10n.levelFigurePro,
    };
  }

  @override
  Widget build(BuildContext context) {
    final label = semanticsLabel ?? _describe(context);
    return Semantics(
      // Its own node: next to text (a card) it would merge into the text.
      container: true,
      label: label,
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: width,
        height: heightFor(width),
        child: CustomPaint(
          painter: AzmLevelPainter(
            figure,
            light: brightness == Brightness.light,
          ),
        ),
      ),
    );
  }
}
