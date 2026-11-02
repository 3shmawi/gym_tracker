import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/usecases/plan_rules.dart';
import 'package:gym_tracker/features/workout/presentation/plan_editor_controller.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/plan_widgets.dart';
import 'package:gym_tracker/features/workout/presentation/workout_format.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// An exercise's names and targets (board 5.4). Every change is saved at
/// once. Data + callbacks only; `PlanExercisePage` wires it.
class PlanExerciseView extends StatelessWidget {
  const new({
    required this.state,
    required this.dayId,
    required this.exerciseId,
    required this.onRetry,
    required this.onRetrySave,
    required this.onBackToPlan,
    required this.onRename,
    required this.onSetTargets,
    required this.onSetSuperset,
    required this.onDelete,
    super.key,
  });

  final AsyncValue<PlanEditorState> state;
  final String dayId;
  final String exerciseId;
  final VoidCallback onRetry;
  final VoidCallback onRetrySave;
  final VoidCallback onBackToPlan;
  final ValueChanged<LocalizedName> onRename;
  final void Function({
    int? sets,
    int? reps,
    int? restSeconds,
    double? weightStep,
  })
  onSetTargets;
  final ValueChanged<bool> onSetSuperset;

  /// Called after the member confirmed.
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppScaffold(
      title: l10n.planExerciseTitle,
      body: switch (state) {
        AsyncData(value: PlanEditorState(saveFailure: final _?)) => EmptyView(
          icon: Icons.error_outline,
          message: l10n.planSaveFailed,
          detail: l10n.planSaveFailedBody,
          action: AppPrimaryButton(
            key: const Key('plan_retry_save'),
            label: l10n.retry,
            onPressed: onRetrySave,
          ),
        ),
        AsyncData(:final value) => _content(context, value),
        AsyncError(:final error) => ErrorView(
          failure: error is AppFailure ? error : UnknownFailure(error),
          onRetry: onRetry,
        ),
        _ => const LoadingView(),
      },
    );
  }

  Widget _content(BuildContext context, PlanEditorState editor) {
    final l10n = context.l10n;
    final day = editor.plan.dayById(dayId);
    final index = day?.exercises.indexWhere((e) => e.id == exerciseId) ?? -1;
    if (day == null || index < 0) {
      return EmptyView(
        icon: Icons.search_off,
        message: l10n.progressNotInPlan,
        action: AppSecondaryButton(
          label: l10n.planBackToPlan,
          onPressed: onBackToPlan,
        ),
      );
    }
    return _Editor(
      view: this,
      day: day,
      index: index,
      locked: editor.lockedDayId == dayId,
    );
  }
}

class _Editor extends StatelessWidget {
  const new({
    required this.view,
    required this.day,
    required this.index,
    required this.locked,
  });

  final PlanExerciseView view;
  final WorkoutDay day;
  final int index;
  final bool locked;

  Exercise get e => day.exercises[index];

  Future<void> _delete(BuildContext context) async {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final ok = await showPlanDeleteSheet(
      context,
      title: l10n.planDeleteExerciseTitle(e.name.of(lang)),
      body: l10n.planDeleteExerciseBody,
      confirmLabel: l10n.planDeleteExercise,
    );
    if (ok) view.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final lang = Localizations.localeOf(context).languageCode;
    final hasNext = index < day.exercises.length - 1;
    final edit = !locked;
    final steps = {...PlanLimits.weightSteps, e.weightStep}.toList()..sort();
    const restStep = PlanLimits.restStep;

    return ListView(
      padding: EdgeInsets.all(AppDimens.md),
      children: [
        PlanSubtitle(
          l10n.planExerciseOf(
            day.name.of(lang),
            index + 1,
            day.exercises.length,
          ),
        ),
        SizedBox(height: AppDimens.sm),
        if (locked) ...[
          AppCard(
            child: Row(
              spacing: AppDimens.sm2,
              children: [
                Icon(Icons.lock_outline, color: palette.trendDown),
                Expanded(
                  child: Text(
                    l10n.planLocked,
                    style: AppTextStyles.body.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: AppDimens.sm),
        ],
        AppCard(
          child: Row(
            spacing: AppDimens.sm,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        e.name.of(lang),
                        style: AppTextStyles.headline.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      e.name.other(lang),
                      style: AppTextStyles.caption.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (edit)
                AppIconButton(
                  key: const Key('plan_rename_exercise'),
                  tooltip: l10n.planRename,
                  icon: Icons.edit_outlined,
                  onPressed: () => unawaited(
                    askName(
                      context,
                      title: l10n.planRename,
                      confirmLabel: l10n.planSave,
                      initial: e.name,
                      onName: view.onRename,
                    ),
                  ),
                ),
            ],
          ),
        ),
        _Section(l10n.planTargets),
        AppCard(
          child: Column(
            children: [
              _TargetRow(
                key: const Key('plan_target_sets'),
                label: l10n.planSets,
                hint: WorkoutFormat.ltr(
                  l10n.planRange(PlanLimits.minSets, PlanLimits.maxSets),
                ),
                value: '${e.targetSets}',
                unit: '',
                decrementLabel: l10n.planSetsLess,
                incrementLabel: l10n.planSetsMore,
                onDecrement: edit && e.targetSets > PlanLimits.minSets
                    ? () => view.onSetTargets(sets: e.targetSets - 1)
                    : null,
                onIncrement: edit && e.targetSets < PlanLimits.maxSets
                    ? () => view.onSetTargets(sets: e.targetSets + 1)
                    : null,
              ),
              Divider(height: 1, color: palette.fillSubtle),
              _TargetRow(
                key: const Key('plan_target_reps'),
                label: l10n.planReps,
                hint: l10n.planRepsHint,
                value: '${e.targetReps}',
                unit: '',
                decrementLabel: l10n.planRepsLess,
                incrementLabel: l10n.planRepsMore,
                onDecrement: edit && e.targetReps > PlanLimits.minReps
                    ? () => view.onSetTargets(reps: e.targetReps - 1)
                    : null,
                onIncrement: edit && e.targetReps < PlanLimits.maxReps
                    ? () => view.onSetTargets(reps: e.targetReps + 1)
                    : null,
              ),
              Divider(height: 1, color: palette.fillSubtle),
              _TargetRow(
                key: const Key('plan_target_rest'),
                label: l10n.planRest,
                hint: e.supersetWithNext
                    ? l10n.planRestAfterPair
                    : l10n.planRestHint(restStep),
                value: '${e.restSeconds}',
                unit: l10n.planSecondsUnit,
                decrementLabel: l10n.planRestLess(restStep),
                incrementLabel: l10n.planRestMore(restStep),
                // The first of a superset pair has no rest of its own.
                onDecrement:
                    edit &&
                        !e.supersetWithNext &&
                        e.restSeconds > PlanLimits.minRest
                    ? () => view.onSetTargets(
                        restSeconds: _down(e.restSeconds, restStep),
                      )
                    : null,
                onIncrement:
                    edit &&
                        !e.supersetWithNext &&
                        e.restSeconds < PlanLimits.maxRest
                    ? () => view.onSetTargets(
                        restSeconds: _up(e.restSeconds, restStep),
                      )
                    : null,
              ),
            ],
          ),
        ),
        _Section(l10n.planWeightStep, hint: l10n.planWeightStepHint),
        Semantics(
          label: l10n.planWeightStep,
          child: Wrap(
            spacing: AppDimens.sm,
            runSpacing: AppDimens.sm,
            children: [
              for (final step in steps)
                AppChoiceChip(
                  key: Key('plan_step_$step'),
                  label: WorkoutFormat.weight(step),
                  semanticLabel: l10n.planWeightStepChoice(
                    WorkoutFormat.weight(step),
                  ),
                  selected: step == e.weightStep,
                  onTap: () {
                    if (edit && step != e.weightStep) {
                      view.onSetTargets(weightStep: step);
                    }
                  },
                ),
            ],
          ),
        ),
        SizedBox(height: AppDimens.md),
        AppCard(
          child: AppSwitchRow(
            key: const Key('plan_superset_switch'),
            label: l10n.planSuperset,
            detail: hasNext
                ? l10n.planSupersetDetail(
                    day.exercises[index + 1].name.of(lang),
                  )
                : l10n.planSupersetLast,
            value: e.supersetWithNext,
            onChanged: edit && hasNext ? view.onSetSuperset : null,
          ),
        ),
        if (edit) ...[
          SizedBox(height: AppDimens.sm),
          Center(
            child: TextButton.icon(
              key: const Key('plan_delete_exercise'),
              onPressed: () => unawaited(_delete(context)),
              icon: Icon(Icons.delete_outline, color: palette.error),
              label: Text(
                l10n.planDeleteExercise,
                style: AppTextStyles.label.copyWith(color: palette.error),
              ),
              style: TextButton.styleFrom(
                minimumSize: const Size(
                  AppDimens.minTouchTarget,
                  AppDimens.minTouchTarget,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Rest moves on the 15 s grid (an odd value like 100 snaps first).
  static int _up(int value, int step) => ((value ~/ step) + 1) * step;
  static int _down(int value, int step) =>
      value % step == 0 ? value - step : (value ~/ step) * step;
}

class _Section extends StatelessWidget {
  const new(this.title, {this.hint});

  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppDimens.xs,
        AppDimens.lg,
        AppDimens.xs,
        AppDimens.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: AppTextStyles.label.copyWith(color: palette.textSecondary),
            ),
          ),
          if (hint != null)
            Text(
              hint!,
              style: AppTextStyles.caption.copyWith(
                color: palette.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

/// Label and hint at the start, an [AppStepper] at the end. On a narrow
/// screen (or large text) the stepper goes under the label.
class _TargetRow extends StatelessWidget {
  const new({
    required this.label,
    required this.hint,
    required this.value,
    required this.unit,
    required this.decrementLabel,
    required this.incrementLabel,
    required this.onDecrement,
    required this.onIncrement,
    super.key,
  });

  final String label;
  final String hint;
  final String value;
  final String unit;
  final String decrementLabel;
  final String incrementLabel;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.body.copyWith(
            fontWeight: FontWeight.w700,
            color: palette.textPrimary,
          ),
        ),
        Text(
          hint,
          style: AppTextStyles.caption.copyWith(color: palette.textSecondary),
        ),
      ],
    );
    final stepperWidth = AppDimens.scaled(200);
    final stepper = AppStepper(
      value: value,
      unit: unit,
      decrementLabel: decrementLabel,
      incrementLabel: incrementLabel,
      onDecrement: onDecrement,
      onIncrement: onIncrement,
    );
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(vertical: AppDimens.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow =
              constraints.maxWidth < stepperWidth + AppDimens.scaled(96) ||
              MediaQuery.textScalerOf(context).scale(1) > 1.2;
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppDimens.sm,
              children: [text, stepper],
            );
          }
          return Row(
            spacing: AppDimens.sm2,
            children: [
              Expanded(child: text),
              SizedBox(width: stepperWidth, child: stepper),
            ],
          );
        },
      ),
    );
  }
}
