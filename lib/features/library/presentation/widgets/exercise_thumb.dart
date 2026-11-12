import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/features/library/data/exercise_images.dart';

/// An exercise's picture on a rounded tile, for plan and workout rows
/// (design "Azm — exercise pictures, workout pill", boards 1–2): the gym's
/// cover when there is one, else the bundled drawing, else a dumbbell. The
/// drawing is a mask tinted with [color] (the text colour by default), so it
/// works in dark and light. Decorative: the row's name says what it is.
class ExerciseThumb extends StatelessWidget {
  const new({
    required this.exerciseId,
    required this.size,
    this.cover,
    this.color,
    this.background,
    super.key,
  });

  final String exerciseId;
  final double size;

  /// The gym's first picture of this exercise; null: the bundled drawing.
  final ImageProvider? cover;

  /// The drawing's tint; null: the primary text colour.
  final Color? color;

  /// The tile's fill; null: the subtle fill.
  final Color? background;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final tint = color ?? palette.textPrimary;
    final fallback = Icon(
      Icons.fitness_center,
      size: size * 0.45,
      color: palette.textTertiary,
    );
    final bundled = ExerciseImages.has(exerciseId)
        ? Image.asset(
            ExerciseImages.thumb(exerciseId),
            fit: BoxFit.contain,
            color: tint,
            colorBlendMode: BlendMode.srcIn,
            errorBuilder: (_, _, _) => fallback,
          )
        : fallback;
    final picture = cover == null
        ? bundled
        : Image(
            image: cover!,
            fit: BoxFit.contain,
            color: tint,
            colorBlendMode: BlendMode.srcIn,
            gaplessPlayback: true,
            frameBuilder: (context, child, frame, sync) =>
                frame != null || sync ? child : bundled,
            errorBuilder: (_, _, _) => bundled,
          );
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.08),
        decoration: BoxDecoration(
          color: background ?? palette.fillSubtle,
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
        alignment: Alignment.center,
        child: picture,
      ),
    );
  }
}

/// [ExerciseThumb] with the exercise's number in the start-top corner (the
/// home screen's plan rows, board 1).
class NumberedExerciseThumb extends StatelessWidget {
  const new({
    required this.number,
    required this.exerciseId,
    this.cover,
    super.key,
  });

  final int number;
  final String exerciseId;
  final ImageProvider? cover;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // With large system text the row needs the room for its words.
    final size = MediaQuery.textScalerOf(context).scale(10) > 11.5
        ? AppDimens.exerciseThumbSmall
        : AppDimens.exerciseThumb;
    final badge = AppDimens.scaled(22);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ExerciseThumb(exerciseId: exerciseId, size: size, cover: cover),
          PositionedDirectional(
            top: -AppDimens.xs,
            start: -AppDimens.xs,
            child: Container(
              constraints: BoxConstraints(minWidth: badge, minHeight: badge),
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.surfaceSolid,
                borderRadius: BorderRadius.circular(AppDimens.radiusFull),
                border: Border.all(color: palette.fillSubtle),
              ),
              // Readable at any text size; grows with it.
              child: Text(
                '$number',
                style: AppTextStyles.label.copyWith(
                  fontSize: math.max(13, AppDimens.scaled(13)),
                  height: 1.2,
                  color: palette.textSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
