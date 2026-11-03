import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/features/library/presentation/library_labels.dart';
import 'package:gym_tracker/features/library/presentation/widgets/exercise_pictures_view.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// One exercise of the library: the picture, names, muscle, equipment and the
/// steps (board "Exercise screen"). Read-only for everyone; when it is opened
/// from the picker it also offers "Add to {day}". Pure UI. The library is
/// bundled, so an id that isn't in it is the only other state.
class ExerciseGuideView extends StatelessWidget {
  const new({
    required this.exercise,
    required this.onBack,
    this.dayName,
    this.alreadyInDay = false,
    this.onAdd,
    this.gymPictures = const [],
    this.movePair = false,
    this.offline = false,
    this.onOpenCredits,
    super.key,
  });

  /// Null: the id isn't in the library (an old or crafted link).
  final LibraryExercise? exercise;
  final VoidCallback onBack;

  /// The day it would be added to; null when just reading.
  final String? dayName;
  final bool alreadyInDay;

  /// Null hides the add button (reading only, or the member may not add).
  final VoidCallback? onAdd;

  /// The pictures the member's gym chose, cover first; empty: the bundled
  /// drawing (or the placeholder). See [ExercisePicturesView].
  final List<ImageProvider> gymPictures;

  /// The gym's two pictures are the start and end of one move.
  final bool movePair;
  final bool offline;

  /// Opens the licenses page from the picture credit.
  final VoidCallback? onOpenCredits;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final e = exercise;
    if (e == null) {
      return AppScaffold(
        title: l10n.exerciseGuideTitle,
        body: EmptyView(
          icon: Icons.search_off,
          message: l10n.exerciseNotFound,
          action: AppSecondaryButton(
            key: const Key('guide_back'),
            label: l10n.libraryTitle,
            onPressed: onBack,
          ),
        ),
      );
    }
    final palette = context.palette;
    final d = e.defaults;
    return AppScaffold(
      title: l10n.exerciseGuideTitle,
      padBottom: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: AppDimens.md,
              ),
              children: [
                ExercisePicturesView(
                  exercise: e,
                  gymPictures: gymPictures,
                  movePair: movePair,
                  offline: offline,
                  onOpenCredits: onOpenCredits,
                ),
                SizedBox(height: AppDimens.sm),
                Semantics(
                  header: true,
                  child: Text(
                    e.name.of(lang),
                    style: AppTextStyles.headline.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  e.name.other(lang),
                  style: AppTextStyles.body.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                SizedBox(height: AppDimens.sm2),
                Wrap(
                  spacing: AppDimens.sm,
                  runSpacing: AppDimens.sm,
                  children: [
                    AppBadge(
                      label: muscleLabel(l10n, e.muscle),
                      tone: AppTone.neutral,
                    ),
                    AppBadge(
                      label: equipmentList(l10n, e.equipment),
                      tone: AppTone.keep,
                    ),
                  ],
                ),
                // Hugs its text: a full-width header box on a tablet is mostly
                // background, which the contrast check misreads.
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: AppSectionLabel(l10n.exerciseHowTo),
                ),
                SizedBox(height: AppDimens.xs),
                AppCard(
                  child: Column(
                    children: [
                      for (final (i, step) in e.steps.indexed)
                        _Step(
                          n: i + 1,
                          text: step.of(lang),
                          divider: i < e.steps.length - 1,
                        ),
                    ],
                  ),
                ),
                SizedBox(height: AppDimens.md),
              ],
            ),
          ),
          if (dayName != null)
            SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  AppDimens.md,
                  AppDimens.sm,
                  AppDimens.md,
                  AppDimens.md,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  spacing: AppDimens.sm,
                  children: [
                    if (onAdd != null || alreadyInDay)
                      SizedBox(
                        width: double.infinity,
                        child: AppPrimaryButton(
                          key: const Key('guide_add'),
                          label: alreadyInDay
                              ? l10n.exerciseAddedTo(dayName!)
                              : l10n.exerciseAddTo(dayName!),
                          onPressed: alreadyInDay ? null : onAdd,
                        ),
                      ),
                    Text(
                      l10n.exerciseStartsAt(
                        d.targetSets,
                        d.targetReps,
                        d.restSeconds,
                      ),
                      textAlign: TextAlign.center,
                      style: AppTextStyles.caption.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const new({required this.n, required this.text, required this.divider});

  final int n;
  final String text;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = context.l10n;
    return Semantics(
      container: true,
      label: '${l10n.exerciseStepLabel(n)}. $text',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: divider
              ? Border(bottom: BorderSide(color: palette.fillSubtle))
              : null,
        ),
        child: Padding(
          padding: EdgeInsetsDirectional.symmetric(vertical: AppDimens.sm2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppDimens.sm2,
            children: [
              Container(
                width: AppDimens.scaled(28),
                height: AppDimens.scaled(28),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$n',
                  style: AppTextStyles.label.copyWith(color: palette.trendUp),
                ),
              ),
              Expanded(
                child: Text(
                  text,
                  style: AppTextStyles.body.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
