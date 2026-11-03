import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/workout/presentation/plan_day_view.dart';
import 'package:gym_tracker/features/workout/presentation/plan_editor_controller.dart';

/// `/plan/<dayId>`: one day's exercises. Unknown ids (old or crafted
/// links) show "This day isn't in your plan".
class PlanDayPage extends ConsumerWidget {
  const new({required this.dayId, super.key});

  final String dayId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(planEditorControllerProvider.notifier);
    return PlanDayView(
      state: ref.watch(planEditorControllerProvider),
      dayId: dayId,
      onRetry: () => unawaited(controller.retry()),
      onRetrySave: () => unawaited(controller.retrySave()),
      onBackToPlan: () => context.go(AppRoutes.plan),
      onOpenExercise: (id) =>
          unawaited(context.push<void>(AppRoutes.planExercise(dayId, id))),
      onRenameDay: (name) => unawaited(controller.renameDay(dayId, name)),
      onAddExercise: (name) => unawaited(controller.addExercise(dayId, name)),
      onRenameExercise: (id, name) =>
          unawaited(controller.renameExercise(dayId, id, name)),
      onDeleteExercise: (id) => unawaited(controller.deleteExercise(dayId, id)),
      onMoveExercise: (from, to) =>
          unawaited(controller.moveExercise(dayId, from, to)),
      onSetSuperset: (id, {required withNext}) =>
          unawaited(controller.setSuperset(dayId, id, withNext: withNext)),
      onResumeWorkout: () => unawaited(context.push<void>(AppRoutes.workout)),
      onPickFromLibrary: () =>
          unawaited(context.push<void>(AppRoutes.libraryFor(dayId))),
    );
  }
}
