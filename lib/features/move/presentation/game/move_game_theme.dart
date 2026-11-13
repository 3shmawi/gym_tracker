import 'package:flutter/painting.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:meta/meta.dart';

/// The game's colours, from the app's palette (a theme or gym-colour
/// change makes a new one). The game draws no text.
@immutable
class MoveGameTheme {
  const new({
    required this.blockTop,
    required this.blockBottom,
    required this.rim,
    required this.steadyRim,
    required this.ghost,
    required this.ground,
    required this.glow,
  });

  factory of(AppPalette palette) => MoveGameTheme(
    blockTop: palette.brand.withValues(alpha: 0.55),
    blockBottom: palette.brandDeep.withValues(alpha: 0.85),
    rim: palette.textPrimary.withValues(alpha: 0.35),
    steadyRim: palette.trendUp,
    ghost: palette.textTertiary,
    ground: palette.textTertiary.withValues(alpha: 0.5),
    glow: palette.brand,
  );

  /// A glass block: a gradient from top to bottom and a thin rim.
  final Color blockTop;
  final Color blockBottom;
  final Color rim;

  /// The rim of a steady rep's block.
  final Color steadyRim;

  /// A half rep's outline.
  final Color ghost;
  final Color ground;

  /// Every fifth block glows once.
  final Color glow;

  @override
  bool operator ==(Object other) =>
      other is MoveGameTheme &&
      other.blockTop == blockTop &&
      other.blockBottom == blockBottom &&
      other.rim == rim &&
      other.steadyRim == steadyRim &&
      other.ghost == ghost &&
      other.ground == ground &&
      other.glow == glow;

  @override
  int get hashCode =>
      Object.hash(blockTop, blockBottom, rim, steadyRim, ghost, ground, glow);
}
