import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/usecases/plan_rules.dart';
import 'package:gym_tracker/features/workout/presentation/plan_editor_controller.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/plan_widgets.dart';
import 'package:gym_tracker/features/workout/presentation/workout_format.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// One day's exercises (boards 5.3, 5.7b, 5.8). Data + callbacks only;
/// `PlanDayPage` wires it.
class PlanDayView extends StatelessWidget {
  const new({
    required this.state,
    required this.dayId,
    required this.onRetry,
    required this.onRetrySave,
    required this.onBackToPlan,
    required this.onOpenExercise,
    required this.onRenameDay,
    required this.onAddExercise,
    required this.onRenameExercise,
    required this.onDeleteExercise,
    required this.onMoveExercise,
    required this.onSetSuperset,
    required this.onResumeWorkout,
    super.key,
  });

  final AsyncValue<PlanEditorState> state;
  final String dayId;
  final VoidCallback onRetry;
  final VoidCallback onRetrySave;
  final VoidCallback onBackToPlan;
  final ValueChanged<String> onOpenExercise;
  final ValueChanged<LocalizedName> onRenameDay;
  final ValueChanged<LocalizedName> onAddExercise;
  final void Function(String exerciseId, LocalizedName name) onRenameExercise;
  final ValueChanged<String> onDeleteExercise;
  final void Function(int from, int to) onMoveExercise;
  final void Function(String exerciseId, {required bool withNext})
  onSetSuperset;
  final VoidCallback onResumeWorkout;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final editor = state.value;
    final day = editor?.plan.dayById(dayId);
    final locked = day != null && editor?.lockedDayId == dayId;
    final permissions = editor?.permissions ?? PlanPermissions.solo;
    return AppScaffold(
      title: day?.name.of(lang) ?? l10n.planTitle,
      actions: [
        if (day != null &&
            !locked &&
            permissions.editStructure &&
            editor?.saveFailure == null)
          AppIconButton(
            key: const Key('plan_rename_day'),
            tooltip: l10n.planRenameDay,
            icon: Icons.edit_outlined,
            onPressed: () => unawaited(
              askName(
                context,
                title: l10n.planRenameDay,
                confirmLabel: l10n.planSave,
                initial: day.name,
                onName: onRenameDay,
              ),
            ),
          ),
      ],
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
        AsyncData(:final value) => switch (day) {
          null => EmptyView(
            icon: Icons.search_off,
            message: l10n.planDayNotFound,
            action: AppSecondaryButton(
              label: l10n.planBackToPlan,
              onPressed: onBackToPlan,
            ),
          ),
          WorkoutDay(exercises: []) when !locked && permissions.editStructure =>
            EmptyView(
              icon: Icons.format_list_bulleted,
              message: l10n.planDayEmptyTitle,
              detail: l10n.planDayEmptyBody,
              action: AppPrimaryButton(
                key: const Key('plan_add_exercise'),
                label: l10n.planAddExercise,
                icon: Icons.add,
                onPressed: () => _addExercise(context),
              ),
            ),
          _ => _Exercises(
            day: day,
            dayIndex: value.plan.indexOfDay(dayId),
            totalDays: value.plan.days.length,
            locked: locked,
            permissions: permissions,
            view: this,
            onAdd: () => _addExercise(context),
          ),
        },
        AsyncError(:final error) => ErrorView(
          failure: error is AppFailure ? error : UnknownFailure(error),
          onRetry: onRetry,
        ),
        _ => const LoadingView(),
      },
    );
  }

  void _addExercise(BuildContext context) => unawaited(
    askName(
      context,
      title: context.l10n.planAddExercise,
      confirmLabel: context.l10n.planAdd,
      onName: onAddExercise,
    ),
  );
}

/// The detail line of an exercise: "3×12 · rest 90 s · step 2.5 kg". The
/// first of a superset pair has no rest of its own.
String planExerciseDetail(AppLocalizations l10n, Exercise e) {
  final target = WorkoutFormat.ltr(
    WorkoutFormat.target(e.targetSets, e.targetReps),
  );
  final step = WorkoutFormat.ltr(WorkoutFormat.weight(e.weightStep));
  return e.supersetWithNext
      ? l10n.planExerciseMetaSuperset(target, step)
      : l10n.planExerciseMeta(
          target,
          WorkoutFormat.ltr('${e.restSeconds}'),
          step,
        );
}

class _Exercises extends StatelessWidget {
  const new({
    required this.day,
    required this.dayIndex,
    required this.totalDays,
    required this.locked,
    required this.permissions,
    required this.view,
    required this.onAdd,
  });

  final WorkoutDay day;
  final int dayIndex;
  final int totalDays;
  final bool locked;
  final PlanPermissions permissions;
  final PlanDayView view;
  final VoidCallback onAdd;

  /// Days and exercises may be changed (the gym lets this member, and no
  /// workout is in progress on this day).
  bool get restructure => !locked && permissions.editStructure;

  /// "A", "B", … inside a superset group, null outside one.
  List<String?> _markers() {
    final markers = <String?>[];
    var inGroup = 0;
    for (final (i, e) in day.exercises.indexed) {
      final continues = i > 0 && day.exercises[i - 1].supersetWithNext;
      if (e.supersetWithNext || continues) {
        inGroup = continues ? inGroup + 1 : 0;
        markers.add(String.fromCharCode(65 + inGroup % 26));
      } else {
        markers.add(null);
      }
    }
    return markers;
  }

  /// The rest after a superset group: the last exercise's in the group.
  int _groupRest(int i) {
    var j = i;
    while (j < day.exercises.length - 1 && day.exercises[j].supersetWithNext) {
      j++;
    }
    return day.exercises[j].restSeconds;
  }

  Future<void> _more(BuildContext context, int i) async {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final list = day.exercises;
    final e = list[i];
    final hasNext = i < list.length - 1;
    final action = await showPlanActionsSheet(
      context,
      title: e.name.of(lang),
      subtitle: [
        e.name.other(lang),
        l10n.planExerciseOf(day.name.of(lang), i + 1, list.length),
      ].join(' · '),
      deleteLabel: l10n.planDeleteExercise,
      superset: e.supersetWithNext,
      supersetDetail: hasNext
          ? l10n.planSupersetDetail(list[i + 1].name.of(lang))
          : l10n.planSupersetLast,
      actions: {
        PlanAction.rename: true,
        PlanAction.superset: hasNext,
        PlanAction.moveUp: i > 0,
        PlanAction.moveDown: hasNext,
        PlanAction.delete: true,
      },
    );
    if (!context.mounted) return;
    switch (action) {
      case PlanAction.rename:
        await askName(
          context,
          title: l10n.planRename,
          confirmLabel: l10n.planSave,
          initial: e.name,
          onName: (name) => view.onRenameExercise(e.id, name),
        );
      case PlanAction.superset:
        view.onSetSuperset(e.id, withNext: !e.supersetWithNext);
      case PlanAction.moveUp:
        view.onMoveExercise(i, i - 1);
      case PlanAction.moveDown:
        view.onMoveExercise(i, i + 1);
      case PlanAction.delete:
        final ok = await showPlanDeleteSheet(
          context,
          title: l10n.planDeleteExerciseTitle(e.name.of(lang)),
          body: l10n.planDeleteExerciseBody,
          confirmLabel: l10n.planDeleteExercise,
        );
        if (ok) view.onDeleteExercise(e.id);
      case null:
        break;
    }
  }

  Widget _row(BuildContext context, int i, List<String?> markers) {
    final l10n = context.l10n;
    final e = day.exercises[i];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PlanRow(
          key: Key('plan_exercise_${e.id}'),
          index: i,
          name: e.name,
          marker: markers[i],
          detail: planExerciseDetail(l10n, e),
          locked: !restructure,
          onTap: () => view.onOpenExercise(e.id),
          onMore: restructure ? () => unawaited(_more(context, i)) : null,
        ),
        if (e.supersetWithNext && i < day.exercises.length - 1)
          SupersetRail(
            label: l10n.planSupersetRail(WorkoutFormat.ltr('${_groupRest(i)}')),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final lang = Localizations.localeOf(context).languageCode;
    final markers = _markers();
    final full = day.exercises.length >= PlanLimits.maxExercisesPerDay;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.all(AppDimens.md),
            children: [
              PlanSubtitle(
                [
                  l10n.todayDayOf(dayIndex + 1, totalDays),
                  day.name.other(lang),
                ].join(' · '),
              ),
              SizedBox(height: AppDimens.sm2),
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
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    key: const Key('plan_resume_workout'),
                    onPressed: view.onResumeWorkout,
                    icon: Icon(
                      Icons.play_arrow_rounded,
                      size: AppDimens.iconMd,
                    ),
                    label: Text(l10n.planResume),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(
                        AppDimens.minTouchTarget,
                        AppDimens.minTouchTarget,
                      ),
                      textStyle: AppTextStyles.label,
                    ),
                  ),
                ),
                AppCard(
                  child: Column(
                    children: [
                      for (final (i, _) in day.exercises.indexed) ...[
                        if (i > 0)
                          Divider(height: 1, color: palette.fillSubtle),
                        _row(context, i, markers),
                      ],
                    ],
                  ),
                ),
                SizedBox(height: AppDimens.sm),
                Text(
                  l10n.planLockedOthers,
                  style: AppTextStyles.caption.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ] else if (!restructure) ...[
                PlanManagedBanner(permissions: permissions),
                SizedBox(height: AppDimens.sm2),
                AppCard(
                  child: Column(
                    children: [
                      for (final (i, _) in day.exercises.indexed) ...[
                        if (i > 0)
                          Divider(height: 1, color: palette.fillSubtle),
                        _row(context, i, markers),
                      ],
                    ],
                  ),
                ),
              ] else ...[
                PlanReorderableCard(
                  itemCount: day.exercises.length,
                  itemId: (i) => day.exercises[i].id,
                  onReorder: view.onMoveExercise,
                  itemBuilder: (context, i) => _row(context, i, markers),
                ),
                SizedBox(height: AppDimens.sm),
                Text(
                  l10n.planDayHint,
                  style: AppTextStyles.caption.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (restructure)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              AppDimens.md,
              AppDimens.sm,
              AppDimens.md,
              AppDimens.md,
            ),
            child: AppSecondaryButton(
              key: const Key('plan_add_exercise'),
              label: l10n.planAddExercise,
              icon: Icons.add,
              onPressed: full ? null : onAdd,
            ),
          ),
      ],
    );
  }
}
