import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/gym/presentation/gym_providers.dart';
import 'package:gym_tracker/features/gym/presentation/gym_sync.dart';
import 'package:gym_tracker/features/gym/presentation/workspace_switcher.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_view.dart';

class NextWorkoutPage extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(nextWorkoutControllerProvider.notifier);
    final signedIn = ref.watch(accountSessionProvider).isSignedIn;
    // Keeps the gyms fresh while signed in, so a revoked membership puts the
    // person back in solo as soon as the app opens.
    if (signedIn) ref.watch(gymControllerProvider);
    final next = ref.watch(nextWorkoutControllerProvider);
    final active = ref.watch(activeWorkoutControllerProvider).value;
    return NextWorkoutView(
      state: next,
      covers: ref.watch(exerciseCoversProvider),
      onRetry: () => unawaited(controller.retry()),
      onUseTemplate: () => unawaited(controller.useTemplate()),
      onOpenSettings: () => unawaited(context.push<void>(AppRoutes.settings)),
      // Only people with a gym account choose where they train.
      onOpenWorkspace: signedIn
          ? () => unawaited(openWorkspaceSwitcher(context, ref))
          : null,
      // Training alone: the way into a gym is one tap from home.
      onJoinGym: signedIn
          ? null
          : () => unawaited(context.push<void>(AppRoutes.joinScan)),
      onOpenProgress: () => unawaited(context.push<void>(AppRoutes.progress)),
      onOpenExercise: (id) =>
          unawaited(context.push<void>(AppRoutes.exerciseHistory(id))),
      onChooseDay: (day) => unawaited(controller.chooseDay(day)),
      onOpenPlan: () => unawaited(context.push<void>(AppRoutes.plan)),
      onBuildPlan: () => unawaited(context.push<void>(AppRoutes.plan)),
      onEditDay: (id) => unawaited(context.push<void>(AppRoutes.planDay(id))),
      // The pill is not on this screen, so its button says what it does.
      inProgress: active != null,
      // Resting only while a set is still to do, as the workout screen does.
      restEndsAt: active?.cursor == null ? null : active?.draft.restEndsAt,
      now: ref.watch(clockProvider),
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
