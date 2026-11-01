import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/workout/presentation/workout_format.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// Weight and reps steppers, prefilled. Used to log a set and to edit one.
class SetSteppers extends StatelessWidget {
  const new({
    required this.weight,
    required this.reps,
    required this.weightStep,
    required this.onWeight,
    required this.onReps,
    super.key,
  });

  final double weight;
  final int reps;
  final double weightStep;
  final ValueChanged<double> onWeight;
  final ValueChanged<int> onReps;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final step = WorkoutFormat.weight(weightStep);
    return Column(
      spacing: AppDimens.sm,
      children: [
        AppStepper(
          key: const Key('weight_stepper'),
          value: WorkoutFormat.weight(weight),
          unit: l10n.unitKg,
          decrementLabel: l10n.workoutRemoveWeight(step),
          incrementLabel: l10n.workoutAddWeight(step),
          onDecrement: weight <= 0
              ? null
              : () => onWeight((weight - weightStep).clamp(0, 1000)),
          onIncrement: weight >= 1000
              ? null
              : () => onWeight(weight + weightStep),
        ),
        AppStepper(
          key: const Key('reps_stepper'),
          value: '$reps',
          unit: l10n.unitReps,
          decrementLabel: l10n.workoutRemoveRep,
          incrementLabel: l10n.workoutAddRep,
          onDecrement: reps <= 0 ? null : () => onReps(reps - 1),
          onIncrement: reps >= 999 ? null : () => onReps(reps + 1),
        ),
      ],
    );
  }
}

/// The dock in log mode: "Set 2 of 3", steppers prefilled with the
/// suggestion, one big Log button.
class LogPanel extends StatefulWidget {
  const new({
    required this.setNumber,
    required this.totalSets,
    required this.targetReps,
    required this.weight,
    required this.reps,
    required this.weightStep,
    required this.onLog,
    this.partnerName,
    super.key,
  });

  final int setNumber;
  final int totalSets;
  final int targetReps;
  final double weight;
  final int reps;
  final double weightStep;

  /// Set inside a superset round: the next exercise, done without rest.
  final String? partnerName;
  final void Function(double weight, int reps) onLog;

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  late double _weight = widget.weight;
  late int _reps = widget.reps;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppDimens.sm2,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.workoutSetOf(widget.setNumber, widget.totalSets),
                style: AppTextStyles.title.copyWith(color: palette.textPrimary),
              ),
            ),
            Text(
              l10n.workoutTarget(widget.targetReps),
              style: AppTextStyles.caption.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
        SetSteppers(
          weight: _weight,
          reps: _reps,
          weightStep: widget.weightStep,
          onWeight: (w) => setState(() => _weight = w),
          onReps: (r) => setState(() => _reps = r),
        ),
        AppPrimaryButton(
          key: const Key('log_set_button'),
          icon: Icons.check,
          label: l10n.workoutLog(WorkoutFormat.weightTimesReps(_weight, _reps)),
          onPressed: () => widget.onLog(_weight, _reps),
        ),
        if (widget.partnerName != null)
          Text(
            l10n.workoutThenPartner(widget.partnerName!),
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }
}
