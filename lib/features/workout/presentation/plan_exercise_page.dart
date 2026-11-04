import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/library/presentation/library_providers.dart';
import 'package:gym_tracker/features/workout/presentation/plan_editor_controller.dart';
import 'package:gym_tracker/features/workout/presentation/plan_exercise_view.dart';

/// `/plan/<dayId>/<exerciseId>`: an exercise's names and targets.
class PlanExercisePage extends ConsumerWidget {
  const new({required this.dayId, required this.exerciseId, super.key});

  final String dayId;
  final String exerciseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(planEditorControllerProvider.notifier);
    return PlanExerciseView(
      state: ref.watch(planEditorControllerProvider),
      dayId: dayId,
      exerciseId: exerciseId,
      onRetry: () => unawaited(controller.retry()),
      onRetrySave: () => unawaited(controller.retrySave()),
      onBackToPlan: () => context.go(AppRoutes.plan),
      onRename: (name) =>
          unawaited(controller.renameExercise(dayId, exerciseId, name)),
      onSetTargets: ({sets, reps, restSeconds, weightStep, unit}) => unawaited(
        controller.setTargets(
          dayId,
          exerciseId,
          sets: sets,
          reps: reps,
          restSeconds: restSeconds,
          weightStep: weightStep,
          unit: unit,
        ),
      ),
      onSetSuperset: (on) =>
          unawaited(controller.setSuperset(dayId, exerciseId, withNext: on)),
      onOpenGuide: ref.read(exerciseLibraryProvider).byId(exerciseId) == null
          ? null
          : () => unawaited(
              context.push<void>(AppRoutes.libraryExercise(exerciseId)),
            ),
      onDelete: () async {
        // Leave first: this screen would show "not in your plan" for a
        // moment otherwise.
        if (context.canPop()) {
          context.pop();
        } else {
          context.go(AppRoutes.planDay(dayId));
        }
        await controller.deleteExercise(dayId, exerciseId);
      },
    );
  }
}
