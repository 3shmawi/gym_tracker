import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_view.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';

class ActiveWorkoutPage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(activeWorkoutControllerProvider.notifier);
    void home() =>
        context.canPop() ? context.pop() : context.go(AppRoutes.home);
    return ActiveWorkoutView(
      state: ref.watch(activeWorkoutControllerProvider),
      now: ref.watch(clockProvider),
      actions: ActiveWorkoutActions(
        onLog: (w, r) => unawaited(controller.logSet(weight: w, reps: r)),
        onEditSet: (i, w, r) =>
            unawaited(controller.editSet(i, weight: w, reps: r)),
        onDeleteSet: (i) => unawaited(controller.deleteSet(i)),
        onAdd15: () =>
            unawaited(controller.addRest(const Duration(seconds: 15))),
        onEndRest: () => unawaited(controller.endRest()),
        onFinish: () async {
          if (await controller.finish() && context.mounted) home();
        },
        onClose: home,
        onRetry: () => unawaited(controller.retry()),
      ),
    );
  }
}
