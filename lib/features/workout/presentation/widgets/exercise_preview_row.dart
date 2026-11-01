import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/workout/domain/entities/next_workout.dart';
import 'package:gym_tracker/features/workout/presentation/workout_format.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// One exercise on the next-workout list: number, name (both languages),
/// target and last time; the suggested weight and its trend at the end.
class ExercisePreviewRow extends StatelessWidget {
  const new({
    required this.number,
    required this.preview,
    this.onTap,
    super.key,
  });

  final int number;
  final ExercisePreview preview;

  /// Opens the exercise's history; null: not tappable.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final lang = Localizations.localeOf(context).languageCode;
    final exercise = preview.exercise;
    final suggestion = preview.suggestion;
    final meta = [
      WorkoutFormat.ltr(
        WorkoutFormat.target(exercise.targetSets, exercise.targetReps),
      ),
      if (preview.lastSets.isNotEmpty)
        l10n.exerciseLast(
          WorkoutFormat.ltr(WorkoutFormat.sets(preview.lastSets)),
        ),
    ].join(' · ');

    final row = MergeSemantics(
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(vertical: AppDimens.sm2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: AppDimens.sm2,
          children: [
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: palette.fillSubtle,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$number',
                style: AppTextStyles.label.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 2,
                children: [
                  Text(
                    exercise.name.of(lang),
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.3,
                      color: palette.textPrimary,
                    ),
                  ),
                  Text(
                    exercise.name.other(lang),
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  Text(
                    meta,
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  if (exercise.supersetWithNext)
                    Row(
                      spacing: AppDimens.xs,
                      children: [
                        Icon(
                          Icons.swap_vert,
                          // Grows with the system text size, like its label.
                          size: MediaQuery.textScalerOf(context).scale(16),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        Flexible(
                          child: Text(
                            l10n.exerciseSuperset,
                            style: AppTextStyles.caption.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: AppDimens.xs,
              children: [
                if (suggestion.weight != null)
                  Text(
                    l10n.weightKg(WorkoutFormat.weight(suggestion.weight!)),
                    style: AppTextStyles.numM.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                AppBadge(
                  label: switch (suggestion.trend) {
                    Trend.up => l10n.trendUp,
                    Trend.keep => l10n.trendKeep,
                    Trend.down => l10n.trendDown,
                    Trend.firstTime => l10n.trendFirstTime,
                  },
                  tone: switch (suggestion.trend) {
                    Trend.up => AppTone.up,
                    Trend.keep => AppTone.keep,
                    Trend.down => AppTone.down,
                    Trend.firstTime => AppTone.fresh,
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return Semantics(
      button: true,
      hint: l10n.progressOpenHint,
      child: InkWell(
        key: Key('exercise_row_${exercise.id}'),
        onTap: onTap,
        child: row,
      ),
    );
  }
}
