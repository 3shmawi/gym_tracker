import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_view.dart';

class NextWorkoutPage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(nextWorkoutControllerProvider.notifier);
    final canStart = ref.watch(activeWorkoutEnabledProvider).value ?? false;
    final next = ref.watch(nextWorkoutControllerProvider);
    return NextWorkoutView(
      state: next,
      onRetry: () => unawaited(controller.retry()),
      onUseTemplate: () => unawaited(controller.useTemplate()),
      onOpenSettings: () => unawaited(context.push<void>(AppRoutes.settings)),
      onStart: canStart && next.value != null
          ? () => unawaited(
              Analytics.capture('workout_started', {
                'day': next.value!.dayIndex + 1,
              }),
            )
          : null,
    );
  }
}
