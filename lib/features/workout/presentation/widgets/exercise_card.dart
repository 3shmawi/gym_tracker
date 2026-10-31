import 'package:flutter/material.dart';
import 'package:gym_tracker/core/adaptive/adaptive.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout.dart';
import 'package:gym_tracker/features/workout/domain/usecases/suggest_next_weight.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// `40` → "40", `42.5` → "42.5".
String formatKg(double kg) =>
    kg == kg.roundToDouble() ? kg.toInt().toString() : kg.toString();

/// One exercise of the day: target, last time, suggestion and — during a
/// workout — the logged sets and a one-tap "log set" button prefilled with
/// the suggested weight.
class ExerciseCard extends StatefulWidget {
  const new({
    required this.exercise,
    required this.lastSets,
    required this.suggestion,
    required this.loggedSets,
    required this.isActive,
    required this.onLog,
    required this.onDelete,
    super.key,
  });

  final PlanExercise exercise;
  final List<LoggedSet> lastSets;
  final WeightSuggestion suggestion;
  final List<LoggedSet> loggedSets;
  final bool isActive;
  final void Function(double weightKg, int reps) onLog;
  final ValueChanged<LoggedSet> onDelete;

  @override
  State<ExerciseCard> createState() => _ExerciseCardState();
}

class _ExerciseCardState extends State<ExerciseCard> {
  late double _weight = _initialWeight();
  late int _reps = _initialReps();

  double _initialWeight() {
    if (widget.loggedSets.isNotEmpty) return widget.loggedSets.last.weightKg;
    return widget.suggestion.weightKg ?? 0;
  }

  int _initialReps() => widget.loggedSets.isNotEmpty
      ? widget.loggedSets.last.reps
      : widget.exercise.targetReps;

  double get _step =>
      widget.exercise.weightStepKg > 0 ? widget.exercise.weightStepKg : 2.5;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final language = Localizations.localeOf(context).languageCode;
    final e = widget.exercise;
    final done = widget.loggedSets.length;
    final nextSet = done + 1;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(e.name(language), style: AppTextStyles.title),
              ),
              if (e.supersetGroup != null)
                Padding(
                  padding: EdgeInsetsDirectional.only(start: AppDimens.sm),
                  child: Chip(
                    label: Text(l10n.workoutSuperset),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
            ],
          ),
          SizedBox(height: AppDimens.xs),
          Text(
            l10n.workoutTarget(e.sets, e.targetReps),
            style: AppTextStyles.caption,
          ),
          SizedBox(height: AppDimens.sm),
          Text(
            widget.lastSets.isEmpty
                ? l10n.workoutFirstTime
                : l10n.workoutLast(
                    widget.lastSets
                        .map((s) => '${formatKg(s.weightKg)}×${s.reps}')
                        .join('  '),
                  ),
            style: AppTextStyles.body,
          ),
          if (widget.suggestion.weightKg case final kg?)
            Row(
              children: [
                Icon(
                  switch (widget.suggestion.trend) {
                    WeightTrend.increase => Icons.trending_up,
                    WeightTrend.decrease => Icons.trending_down,
                    _ => Icons.trending_flat,
                  },
                  size: AppDimens.iconMd,
                  color: theme.colorScheme.primary,
                ),
                SizedBox(width: AppDimens.xs),
                Text(
                  l10n.workoutSuggested(l10n.workoutKg(formatKg(kg))),
                  style: AppTextStyles.label,
                ),
              ],
            ),
          if (widget.isActive) ...[
            if (widget.loggedSets.isNotEmpty) ...[
              SizedBox(height: AppDimens.sm),
              Wrap(
                spacing: AppDimens.sm,
                runSpacing: AppDimens.xs,
                children: [
                  for (final s in widget.loggedSets)
                    InputChip(
                      label: Text(
                        '${s.setNumber}: ${formatKg(s.weightKg)}×${s.reps}',
                      ),
                      deleteButtonTooltipMessage: l10n.workoutDeleteSet(
                        s.setNumber,
                      ),
                      onDeleted: () => widget.onDelete(s),
                    ),
                ],
              ),
            ],
            SizedBox(height: AppDimens.md),
            Row(
              children: [
                Expanded(
                  child: _Stepper(
                    label: l10n.workoutWeight,
                    value: l10n.workoutKg(formatKg(_weight)),
                    onMinus: _weight - _step >= 0
                        ? () => setState(() => _weight -= _step)
                        : null,
                    onPlus: () => setState(() => _weight += _step),
                  ),
                ),
                SizedBox(width: AppDimens.sm),
                Expanded(
                  child: _Stepper(
                    label: l10n.workoutReps,
                    value: '$_reps',
                    onMinus: _reps > 1 ? () => setState(() => _reps--) : null,
                    onPlus: () => setState(() => _reps++),
                  ),
                ),
              ],
            ),
            SizedBox(height: AppDimens.md),
            SizedBox(
              height: AppDimens.buttonHeight * 1.3,
              child: AdaptiveButton(
                key: Key('log_set_${e.exerciseId}'),
                onPressed: () => widget.onLog(_weight, _reps),
                child: Text(
                  done >= e.sets
                      ? l10n.workoutExtraSet
                      : l10n.workoutLogSet(nextSet),
                  style: AppTextStyles.title,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A big − value + control, easy to hit with sweaty hands.
class _Stepper extends StatelessWidget {
  const new({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        Text(label, style: AppTextStyles.caption),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            AppIconButton(
              icon: Icons.remove,
              tooltip: l10n.workoutDecrease(label),
              onPressed: onMinus ?? () {},
            ),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value, style: AppTextStyles.headline),
              ),
            ),
            AppIconButton(
              icon: Icons.add,
              tooltip: l10n.workoutIncrease(label),
              onPressed: onPlus,
            ),
          ],
        ),
      ],
    );
  }
}
