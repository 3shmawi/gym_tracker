import 'package:flutter/material.dart';
import 'package:gym_tracker/core/adaptive/adaptive.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/exercise_card.dart';
import 'package:gym_tracker/features/workout/presentation/workout_controller.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// The workout screen, pure UI: state in, callbacks out.
class WorkoutView extends StatelessWidget {
  const new({
    required this.state,
    required this.pendingSync,
    required this.onRefresh,
    required this.onStart,
    required this.onLog,
    required this.onDeleteSet,
    required this.onComplete,
    this.message,
    super.key,
  });

  final WorkoutState state;
  final int pendingSync;
  final Future<void> Function() onRefresh;
  final VoidCallback onStart;
  final void Function(PlanExercise exercise, double weightKg, int reps) onLog;
  final ValueChanged<LoggedSet> onDeleteSet;
  final VoidCallback onComplete;

  /// One-off message on top, e.g. after finishing a workout.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final language = Localizations.localeOf(context).languageCode;
    final plan = state.plan;
    final day = state.day;

    if (plan == null || day == null) {
      return RefreshIndicator.adaptive(
        onRefresh: onRefresh,
        child: ListView(
          children: [
            SizedBox(height: AppDimens.xl * 3),
            EmptyView(message: l10n.workoutNoPlan, icon: Icons.fitness_center),
          ],
        ),
      );
    }

    return RefreshIndicator.adaptive(
      onRefresh: onRefresh,
      child: ListView(
        padding: EdgeInsets.all(AppDimens.md),
        children: [
          if (message != null) ...[
            AppCard(
              child: Text(
                message!,
                style: AppTextStyles.label,
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: AppDimens.md),
          ],
          Semantics(
            header: true,
            child: Text(day.name(language), style: AppTextStyles.display),
          ),
          Text(
            l10n.workoutDayOf(day.dayOrder, plan.days.length),
            style: AppTextStyles.body,
          ),
          if (pendingSync > 0) ...[
            SizedBox(height: AppDimens.xs),
            Row(
              children: [
                Icon(Icons.cloud_upload_outlined, size: AppDimens.iconMd),
                SizedBox(width: AppDimens.xs),
                Expanded(
                  child: Text(
                    l10n.workoutPendingSync,
                    style: AppTextStyles.caption,
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: AppDimens.md),
          if (!state.isActive) ...[
            _BigButton(
              key: const Key('workout_start_button'),
              label: l10n.workoutStart,
              onPressed: onStart,
            ),
            SizedBox(height: AppDimens.md),
          ],
          for (final exercise in day.exercises) ...[
            ExerciseCard(
              // A new key per session resets the steppers to the suggestion.
              key: ValueKey('${state.session?.id}-${exercise.exerciseId}'),
              exercise: exercise,
              lastSets: state.lastSets[exercise.exerciseId] ?? const [],
              suggestion: state.suggestionFor(exercise),
              loggedSets: state.setsFor(exercise.exerciseId),
              isActive: state.isActive,
              onLog: (kg, reps) => onLog(exercise, kg, reps),
              onDelete: onDeleteSet,
            ),
            SizedBox(height: AppDimens.md),
          ],
          if (state.isActive)
            _BigButton(
              key: const Key('workout_complete_button'),
              label: l10n.workoutComplete,
              onPressed: onComplete,
            ),
          SizedBox(height: AppDimens.xl),
        ],
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const new({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: AppDimens.buttonHeight * 1.3,
    child: AdaptiveButton(
      onPressed: onPressed,
      child: Text(label, style: AppTextStyles.title),
    ),
  );
}
