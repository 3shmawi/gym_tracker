import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/features/library/data/exercise_images.dart';
import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// The picture of an exercise: its bundled drawing (`ExerciseImages`), drawn
/// with no background in the theme's text colour. An exercise with no
/// drawing, or one that fails to load, shows a diagonal-hatched tile with a
/// dumbbell of the same size, so the screens never move. [large] is the hero
/// on the exercise screen, otherwise the small tile of a list row.
class ExerciseIllustration extends StatelessWidget {
  const new({
    required this.exercise,
    this.large = false,
    this.height,
    super.key,
  });

  final LibraryExercise exercise;
  final bool large;

  /// The large picture's height; null: 210 (scaled). The picture stage of
  /// the exercise screen passes the room inside its card.
  final double? height;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = context.l10n;
    final size = AppDimens.scaled(52);
    final height = large ? (this.height ?? AppDimens.scaled(210)) : size;
    final placeholder = _placeholder(context, size);
    if (!ExerciseImages.has(exercise.id)) return placeholder;
    final name = exercise.name.of(Localizations.localeOf(context).languageCode);
    // The drawing is a transparent mask: tinting it with the text colour
    // makes it right in dark and light, and it has no background.
    final picture = SizedBox(
      width: large ? double.infinity : null,
      height: large ? height : null,
      child: Image.asset(
        large
            ? ExerciseImages.large(exercise.id)
            : ExerciseImages.thumb(exercise.id),
        fit: BoxFit.contain,
        color: palette.textPrimary,
        colorBlendMode: BlendMode.srcIn,
        errorBuilder: (_, _, _) => placeholder,
      ),
    );
    // A list row's tile is decorative (the name beside it says what it is):
    // the drawing on a rounded tile (design board 5.1). The hero is described.
    if (!large) return ExcludeSemantics(child: ExerciseTile(child: picture));
    return Semantics(
      image: true,
      label: l10n.exerciseIllustrationLabel(name),
      excludeSemantics: true,
      child: picture,
    );
  }

  Widget _placeholder(BuildContext context, double size) {
    final palette = context.palette;
    final l10n = context.l10n;
    final hatch = _Hatch(
      color: palette.fillSubtle,
      gap: AppDimens.scaled(large ? 20 : 12),
    );
    // Decorative: the name next to it already says what the exercise is, and
    // the caption (the large one) is read as text.
    return ExcludeSemantics(
      excluding: !large,
      child: SizedBox(
        width: large ? double.infinity : size,
        height: large ? (height ?? AppDimens.scaled(210)) : size,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            large ? AppDimens.radiusXl : AppDimens.radiusMd,
          ),
          child: CustomPaint(
            painter: hatch,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: AppDimens.sm,
                children: [
                  Icon(
                    Icons.fitness_center,
                    size: AppDimens.scaled(large ? 56 : 24),
                    color: palette.textTertiary,
                  ),
                  if (large)
                    // On a plain chip: the hatch behind thin letters would
                    // make them hard to read.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.surfaceSolid,
                        borderRadius: BorderRadius.circular(
                          AppDimens.radiusFull,
                        ),
                      ),
                      child: Padding(
                        padding: EdgeInsetsDirectional.symmetric(
                          horizontal: AppDimens.sm2,
                          vertical: AppDimens.xs,
                        ),
                        child: Text(
                          l10n.exerciseIllustrationSoon,
                          style: AppTextStyles.caption.copyWith(
                            color: palette.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The rounded tile of a library row (52, radius 14, the subtle fill), with
/// the drawing inset 6 (design board 5.1).
class ExerciseTile extends StatelessWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: AppDimens.scaled(52),
    height: AppDimens.scaled(52),
    padding: EdgeInsets.all(AppDimens.scaled(6)),
    decoration: BoxDecoration(
      color: context.palette.fillSubtle,
      borderRadius: BorderRadius.circular(AppDimens.scaled(14)),
    ),
    child: child,
  );
}

class _Hatch extends CustomPainter {
  const new({required this.color, required this.gap});

  final Color color;
  final double gap;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
    final line = Paint()
      ..color = color
      ..strokeWidth = gap / 3;
    for (var x = -size.height; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), line);
    }
  }

  @override
  bool shouldRepaint(_Hatch old) => old.color != color || old.gap != gap;
}
