import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/features/library/data/exercise_images.dart';
import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/features/library/presentation/widgets/exercise_illustration.dart';

/// A library row's tile with the first picture the gym chose (design board
/// 5.1): tinted like the bundled drawings, with a small gym mark at the end
/// corner. While it loads, or when it fails, the bundled tile shows.
/// Decorative: the row's name says what it is.
class GymPictureTile extends StatelessWidget {
  const new({required this.image, required this.exercise, super.key});

  final ImageProvider image;
  final LibraryExercise exercise;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final size = AppDimens.scaled(52);
    // While loading or failed: the bundled drawing on the same tile.
    final fallback = ExerciseImages.has(exercise.id)
        ? Image.asset(
            ExerciseImages.thumb(exercise.id),
            fit: BoxFit.contain,
            color: palette.textPrimary,
            colorBlendMode: BlendMode.srcIn,
          )
        : const SizedBox.shrink() as Widget;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          children: [
            Positioned.fill(
              child: ExerciseTile(
                child: Image(
                  image: image,
                  fit: BoxFit.contain,
                  color: palette.textPrimary,
                  colorBlendMode: BlendMode.srcIn,
                  gaplessPlayback: true,
                  frameBuilder: (context, child, frame, sync) =>
                      frame != null || sync ? child : fallback,
                  errorBuilder: (_, _, _) => fallback,
                ),
              ),
            ),
            PositionedDirectional(
              bottom: AppDimens.scaled(3),
              end: AppDimens.scaled(3),
              child: Container(
                width: AppDimens.scaled(16),
                height: AppDimens.scaled(16),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.shield_outlined,
                  size: AppDimens.scaled(10),
                  color: scheme.onPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
