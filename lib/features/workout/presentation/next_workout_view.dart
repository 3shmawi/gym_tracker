import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/adaptive/adaptive.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/workout/domain/entities/next_workout.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/exercise_preview_row.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/level_card.dart';
import 'package:gym_tracker/l10n/l10n.dart';
import 'package:intl/intl.dart';

/// The home screen: the workout waiting for the member. Data + callbacks
/// only; `NextWorkoutPage` wires it.
class NextWorkoutView extends StatelessWidget {
  const new({
    required this.state,
    required this.onRetry,
    required this.onUseTemplate,
    required this.onOpenSettings,
    required this.onChooseDay,
    this.onStart,
    this.onOpenProgress,
    this.onOpenExercise,
    this.onOpenPlan,
    this.onOpenWorkspace,
    this.onBuildPlan,
    this.onEditDay,
    super.key,
  });

  /// null value: no plan yet.
  final AsyncValue<NextWorkout?> state;
  final VoidCallback onRetry;
  final VoidCallback onUseTemplate;
  final VoidCallback onOpenSettings;

  /// Opens the progress screen.
  final VoidCallback? onOpenProgress;

  /// Opens one exercise's history (its id).
  final ValueChanged<String>? onOpenExercise;

  /// The member picked which plan day (0-based) is next.
  final ValueChanged<int> onChooseDay;

  /// Hidden while null (the active workout isn't available yet).
  final VoidCallback? onStart;

  /// Opens the plan editor ("Your plan", the list button on the bar).
  final VoidCallback? onOpenPlan;

  /// "Build your plan" on the no-plan screen: the editor with an empty plan.
  final VoidCallback? onBuildPlan;

  /// Opens a plan day in the editor (its id): "Add exercises" when the
  /// waiting day has none.
  final ValueChanged<String>? onEditDay;

  /// "Where are you training?": only for people with a gym account.
  final VoidCallback? onOpenWorkspace;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppScaffold(
      title: l10n.todayTitle,
      actions: [
        if (onOpenWorkspace != null)
          AppIconButton(
            key: const Key('home_workspace_button'),
            tooltip: l10n.switchTitle,
            icon: Icons.swap_horiz,
            onPressed: onOpenWorkspace!,
          ),
        if (onOpenPlan != null && state.value != null)
          AppIconButton(
            key: const Key('home_plan_button'),
            tooltip: l10n.planTitle,
            icon: Icons.format_list_bulleted,
            onPressed: onOpenPlan!,
          ),
        if (onOpenProgress != null)
          AppIconButton(
            key: const Key('home_progress_button'),
            tooltip: l10n.progressTitle,
            icon: Icons.show_chart,
            onPressed: onOpenProgress!,
          ),
        AppIconButton(
          key: const Key('home_settings_button'),
          tooltip: l10n.settingsTitle,
          icon: AdaptiveIcons.settings(context),
          onPressed: onOpenSettings,
        ),
      ],
      body: switch (state) {
        AsyncData(value: final next?) => _Workout(
          next: next,
          onStart: onStart,
          onChooseDay: onChooseDay,
          onOpenExercise: onOpenExercise,
          onEditDay: onEditDay,
        ),
        AsyncData() => EmptyView(
          icon: Icons.fitness_center,
          message: l10n.todayNoPlan,
          action: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: AppDimens.sm,
            children: [
              if (onBuildPlan != null)
                AppPrimaryButton(
                  key: const Key('build_plan_button'),
                  label: l10n.planBuild,
                  onPressed: onBuildPlan,
                ),
              if (onBuildPlan != null)
                AppSecondaryButton(
                  key: const Key('use_template_button'),
                  label: l10n.todayUseTemplate,
                  onPressed: onUseTemplate,
                )
              else
                AppPrimaryButton(
                  key: const Key('use_template_button'),
                  label: l10n.todayUseTemplate,
                  onPressed: onUseTemplate,
                ),
            ],
          ),
        ),
        AsyncError(:final error) => ErrorView(
          failure: error is AppFailure ? error : UnknownFailure(error),
          onRetry: onRetry,
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _Workout extends StatelessWidget {
  const new({
    required this.next,
    required this.onStart,
    required this.onChooseDay,
    this.onOpenExercise,
    this.onEditDay,
  });

  final NextWorkout next;
  final ValueChanged<String>? onEditDay;
  final ValueChanged<String>? onOpenExercise;
  final VoidCallback? onStart;
  final ValueChanged<int> onChooseDay;

  Future<void> _pickDay(BuildContext context) async {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final picked = await showAppSheet<int>(
      context: context,
      builder: (sheet) => SingleChildScrollView(
        padding: EdgeInsetsDirectional.fromSTEB(
          AppDimens.md,
          0,
          AppDimens.md,
          AppDimens.lg,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.todayChooseDay,
                style: AppTextStyles.title.copyWith(
                  color: sheet.palette.textPrimary,
                ),
              ),
            ),
            SizedBox(height: AppDimens.xs),
            Text(
              l10n.todayChooseDayHint,
              style: AppTextStyles.caption.copyWith(
                color: sheet.palette.textSecondary,
              ),
            ),
            SizedBox(height: AppDimens.sm),
            for (final (i, day) in next.days.indexed)
              AppChoiceRow(
                key: Key('choose_day_$i'),
                label: l10n.todayDayN(i + 1),
                detail: day.name.of(lang),
                selected: i == next.dayIndex,
                onTap: () => Navigator.of(sheet).pop(i),
              ),
          ],
        ),
      ),
    );
    if (picked != null && picked != next.dayIndex) onChooseDay(picked);
  }

  /// Starts right away, or asks first when a workout was already finished
  /// today (a second session is allowed, never blocked).
  Future<void> _start(BuildContext context) async {
    if (!next.trainedToday) return onStart?.call();
    final l10n = context.l10n;
    final go = await showAppSheet<bool>(
      context: context,
      builder: (sheet) => Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          AppDimens.md,
          0,
          AppDimens.md,
          AppDimens.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppDimens.sm2,
          children: [
            Semantics(
              header: true,
              child: Text(
                l10n.todayAgainTitle,
                style: AppTextStyles.title.copyWith(
                  color: sheet.palette.textPrimary,
                ),
              ),
            ),
            Text(
              l10n.todayAgainBody,
              style: AppTextStyles.body.copyWith(
                color: sheet.palette.textSecondary,
              ),
            ),
            AppPrimaryButton(
              key: const Key('start_again_confirm'),
              icon: Icons.play_arrow_rounded,
              label: l10n.todayAgainStart,
              onPressed: () => Navigator.of(sheet).pop(true),
            ),
            AppSecondaryButton(
              key: const Key('start_again_cancel'),
              label: l10n.workoutCancel,
              onPressed: () => Navigator.of(sheet).pop(false),
            ),
          ],
        ),
      ),
    );
    if (go ?? false) onStart?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final lang = Localizations.localeOf(context).languageCode;
    final waitingSince = next.waitingSince;
    final dayOf = l10n.todayDayOf(next.dayIndex + 1, next.totalDays);
    final empty = next.exercises.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.all(AppDimens.md),
            children: [
              if (waitingSince != null) ...[
                AppCard(
                  child: Row(
                    spacing: AppDimens.sm2,
                    children: [
                      Icon(Icons.schedule, color: palette.trendDown),
                      Expanded(
                        child: Text(
                          l10n.todayWaiting(
                            DateFormat.EEEE(l10n.localeName)
                                .format(waitingSince),
                          ),
                          style: AppTextStyles.body.copyWith(
                            color: palette.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: AppDimens.md),
              ],
              Row(
                children: [
                  Expanded(
                    child: Text(
                      dayOf,
                      style: AppTextStyles.label.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('change_day_button'),
                    onPressed: () => _pickDay(context),
                    icon: const Icon(Icons.swap_horiz),
                    label: Text(l10n.todayChangeDay),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(
                        AppDimens.minTouchTarget,
                        AppDimens.minTouchTarget,
                      ),
                      textStyle: AppTextStyles.label,
                    ),
                  ),
                ],
              ),
              Semantics(
                header: true,
                child: Text(
                  next.day.name.of(lang),
                  style: AppTextStyles.display.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
              SizedBox(height: AppDimens.xs),
              Text(
                l10n.todaySummary(next.exercises.length, next.day.totalSets),
                style: AppTextStyles.caption.copyWith(
                  color: palette.textSecondary,
                ),
              ),
              SizedBox(height: AppDimens.sm2),
              AppSegmentedProgress(
                total: next.totalDays,
                current: next.dayIndex + 1,
                semanticLabel: dayOf,
              ),
              SizedBox(height: AppDimens.md),
              if (empty)
                AppCard(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: AppDimens.sm),
                    child: Column(
                      spacing: AppDimens.xs,
                      children: [
                        Icon(
                          Icons.format_list_bulleted,
                          color: palette.textSecondary,
                        ),
                        Text(
                          l10n.todayDayEmptyTitle,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.title.copyWith(
                            color: palette.textPrimary,
                          ),
                        ),
                        Text(
                          l10n.todayDayEmptyBody,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.caption.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                AppCard(
                  child: Column(
                    children: [
                      for (final (i, preview) in next.exercises.indexed) ...[
                        if (i > 0)
                          Divider(height: 1, color: palette.fillSubtle),
                        ExercisePreviewRow(
                          number: i + 1,
                          preview: preview,
                          onTap: onOpenExercise == null
                              ? null
                              : () => onOpenExercise!(preview.exercise.id),
                        ),
                      ],
                    ],
                  ),
                ),
              SizedBox(height: AppDimens.md),
              LevelCard(progress: next.level),
            ],
          ),
        ),
        if (empty && onEditDay != null)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              AppDimens.md,
              AppDimens.sm,
              AppDimens.md,
              AppDimens.md,
            ),
            child: AppPrimaryButton(
              key: const Key('home_add_exercises'),
              label: l10n.todayAddExercises,
              icon: Icons.add,
              onPressed: () => onEditDay!(next.day.id),
            ),
          )
        else if (onStart != null && !empty)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              AppDimens.md,
              AppDimens.sm,
              AppDimens.md,
              AppDimens.md,
            ),
            child: AppPrimaryButton(
              label: l10n.todayStart,
              icon: Icons.play_arrow_rounded,
              onPressed: () => _start(context),
            ),
          ),
      ],
    );
  }
}
