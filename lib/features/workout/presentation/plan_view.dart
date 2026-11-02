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
import 'package:gym_tracker/l10n/l10n.dart';

/// "Your plan": the days in order (boards 5.1, 5.2, 5.7a, 5.9). Data +
/// callbacks only; `PlanPage` wires it.
class PlanView extends StatelessWidget {
  const new({
    required this.state,
    required this.onRetry,
    required this.onRetrySave,
    required this.onOpenDay,
    required this.onAddDay,
    required this.onRenameDay,
    required this.onDeleteDay,
    required this.onMoveDay,
    super.key,
  });

  final AsyncValue<PlanEditorState> state;
  final VoidCallback onRetry;
  final VoidCallback onRetrySave;
  final ValueChanged<String> onOpenDay;
  final ValueChanged<LocalizedName> onAddDay;
  final void Function(String dayId, LocalizedName name) onRenameDay;
  final ValueChanged<String> onDeleteDay;
  final void Function(int from, int to) onMoveDay;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppScaffold(
      title: l10n.planTitle,
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
        AsyncData(:final value) when value.plan.days.isEmpty => EmptyView(
          icon: Icons.fitness_center,
          message: l10n.planEmptyTitle,
          detail: l10n.planEmptyBody,
          action: AppPrimaryButton(
            key: const Key('plan_add_first_day'),
            label: l10n.planAddFirstDay,
            icon: Icons.add,
            onPressed: () => _addDay(context),
          ),
        ),
        AsyncData(:final value) => _Days(
          editor: value,
          onOpenDay: onOpenDay,
          onAddDay: () => _addDay(context),
          onRenameDay: onRenameDay,
          onDeleteDay: onDeleteDay,
          onMoveDay: onMoveDay,
        ),
        AsyncError(:final error) => ErrorView(
          failure: error is AppFailure ? error : UnknownFailure(error),
          onRetry: onRetry,
        ),
        _ => const LoadingView(),
      },
    );
  }

  void _addDay(BuildContext context) => unawaited(
    askName(
      context,
      title: context.l10n.planAddDay,
      confirmLabel: context.l10n.planAdd,
      onName: onAddDay,
    ),
  );
}

class _Days extends StatelessWidget {
  const new({
    required this.editor,
    required this.onOpenDay,
    required this.onAddDay,
    required this.onRenameDay,
    required this.onDeleteDay,
    required this.onMoveDay,
  });

  final PlanEditorState editor;
  final ValueChanged<String> onOpenDay;
  final VoidCallback onAddDay;
  final void Function(String dayId, LocalizedName name) onRenameDay;
  final ValueChanged<String> onDeleteDay;
  final void Function(int from, int to) onMoveDay;

  Future<void> _more(BuildContext context, int i) async {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final days = editor.plan.days;
    final day = days[i];
    final locked = day.id == editor.lockedDayId;
    final action = await showPlanActionsSheet(
      context,
      title: day.name.of(lang),
      subtitle: locked
          ? l10n.planLocked
          : days.length == 1
          ? l10n.planLastDay
          : l10n.todayDayOf(i + 1, days.length),
      deleteLabel: l10n.planDeleteDay,
      actions: {
        PlanAction.rename: !locked,
        PlanAction.moveUp: i > 0,
        PlanAction.moveDown: i < days.length - 1,
        PlanAction.delete: !locked && days.length > 1,
      },
    );
    if (!context.mounted) return;
    switch (action) {
      case PlanAction.rename:
        await askName(
          context,
          title: l10n.planRenameDay,
          confirmLabel: l10n.planSave,
          initial: day.name,
          onName: (name) => onRenameDay(day.id, name),
        );
      case PlanAction.moveUp:
        onMoveDay(i, i - 1);
      case PlanAction.moveDown:
        onMoveDay(i, i + 1);
      case PlanAction.delete:
        final ok = await showPlanDeleteSheet(
          context,
          title: l10n.planDeleteDayTitle(day.name.of(lang)),
          body: l10n.planDeleteDayBody,
          confirmLabel: l10n.planDeleteDay,
        );
        if (ok) onDeleteDay(day.id);
      case PlanAction.superset || null:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final days = editor.plan.days;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.all(AppDimens.md),
            children: [
              PlanSubtitle(l10n.planAutosave),
              SizedBox(height: AppDimens.xs),
              Text(
                l10n.planHint,
                style: AppTextStyles.caption.copyWith(
                  color: palette.textSecondary,
                ),
              ),
              SizedBox(height: AppDimens.sm2),
              PlanReorderableCard(
                itemCount: days.length,
                itemId: (i) => days[i].id,
                onReorder: onMoveDay,
                itemBuilder: (context, i) {
                  final day = days[i];
                  return PlanRow(
                    key: Key('plan_day_${day.id}'),
                    index: i,
                    name: day.name,
                    detail: l10n.todaySummary(
                      day.exercises.length,
                      day.totalSets,
                    ),
                    badge: day.id == editor.lockedDayId
                        ? AppBadge(
                            label: l10n.planInProgress,
                            tone: AppTone.down,
                          )
                        : day.id == editor.nextDayId
                        ? AppBadge(label: l10n.planNext, tone: AppTone.keep)
                        : null,
                    onTap: () => onOpenDay(day.id),
                    onMore: () => unawaited(_more(context, i)),
                  );
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            AppDimens.md,
            AppDimens.sm,
            AppDimens.md,
            AppDimens.md,
          ),
          child: AppSecondaryButton(
            key: const Key('plan_add_day'),
            label: l10n.planAddDay,
            icon: Icons.add,
            onPressed: days.length >= PlanLimits.maxDays ? null : onAddDay,
          ),
        ),
      ],
    );
  }
}
