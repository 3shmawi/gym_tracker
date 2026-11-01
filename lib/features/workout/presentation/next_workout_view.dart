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
    this.onStart,
    super.key,
  });

  /// null value: no plan yet.
  final AsyncValue<NextWorkout?> state;
  final VoidCallback onRetry;
  final VoidCallback onUseTemplate;
  final VoidCallback onOpenSettings;

  /// Hidden while null (the active workout isn't available yet).
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppScaffold(
      title: l10n.todayTitle,
      actions: [
        AppIconButton(
          key: const Key('home_settings_button'),
          tooltip: l10n.settingsTitle,
          icon: AdaptiveIcons.settings(context),
          onPressed: onOpenSettings,
        ),
      ],
      body: switch (state) {
        AsyncData(value: final next?) => _Workout(next: next, onStart: onStart),
        AsyncData() => EmptyView(
          icon: Icons.fitness_center,
          message: l10n.todayNoPlan,
          action: AppPrimaryButton(
            key: const Key('use_template_button'),
            label: l10n.todayUseTemplate,
            onPressed: onUseTemplate,
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
  const new({required this.next, required this.onStart});

  final NextWorkout next;
  final VoidCallback? onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final lang = Localizations.localeOf(context).languageCode;
    final waitingSince = next.waitingSince;
    final dayOf = l10n.todayDayOf(next.dayIndex + 1, next.totalDays);

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
              Text(
                dayOf,
                style: AppTextStyles.label.copyWith(
                  color: palette.textSecondary,
                ),
              ),
              SizedBox(height: AppDimens.xs),
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
              AppCard(
                child: Column(
                  children: [
                    for (final (i, preview) in next.exercises.indexed) ...[
                      if (i > 0) Divider(height: 1, color: palette.fillSubtle),
                      ExercisePreviewRow(number: i + 1, preview: preview),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (onStart != null)
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
              onPressed: onStart,
            ),
          ),
      ],
    );
  }
}
