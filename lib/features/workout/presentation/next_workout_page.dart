import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_view.dart';

class NextWorkoutPage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(nextWorkoutControllerProvider.notifier);
    final next = ref.watch(nextWorkoutControllerProvider);
    return NextWorkoutView(
      state: next,
      onRetry: () => unawaited(controller.retry()),
      onUseTemplate: () => unawaited(controller.useTemplate()),
      onOpenSettings: () => unawaited(context.push<void>(AppRoutes.settings)),
      onChooseDay: (day) => unawaited(controller.chooseDay(day)),
      onStart: next.value == null
          ? null
          : () async {
              if (await controller.startWorkout() && context.mounted) {
                ref.invalidate(activeWorkoutControllerProvider);
                await context.push<void>(AppRoutes.workout);
              }
            },
    );
  }
}
