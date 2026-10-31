import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/adaptive/adaptive.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/workout/presentation/workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/workout_view.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// Connects [WorkoutView] to [WorkoutController].
class WorkoutPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<WorkoutPage> createState() => _WorkoutPageState();
}

class _WorkoutPageState extends ConsumerState<WorkoutPage> {
  String? _message;

  WorkoutController get _controller =>
      ref.read(workoutControllerProvider.notifier);

  Future<void> _complete(WorkoutState state) async {
    final l10n = context.l10n;
    final confirmed = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: Text(l10n.workoutCompleteTitle),
        content: Text(
          state.allSetsLogged
              ? l10n.workoutCompleteBody
              : l10n.workoutCompleteBodyMissing,
        ),
        actions: [
          AdaptiveDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          AdaptiveDialogAction(
            key: const Key('workout_complete_confirm'),
            isDefault: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.workoutComplete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final next = await _controller.complete();
    if (!mounted || next == null) return;
    final language = Localizations.localeOf(context).languageCode;
    setState(() => _message = l10n.workoutCompleted(next.name(language)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final async = ref.watch(workoutControllerProvider);
    final pending = ref.watch(workoutPendingSyncProvider).value ?? 0;

    return AppScaffold(
      title: l10n.workoutTitle,
      actions: [
        AppIconButton(
          key: const Key('home_settings_button'),
          tooltip: l10n.settingsTitle,
          icon: AdaptiveIcons.settings(context),
          onPressed: () => unawaited(context.push<void>(AppRoutes.settings)),
        ),
      ],
      body: switch (async) {
        AsyncData(:final value) => WorkoutView(
          state: value,
          pendingSync: pending,
          message: value.isActive ? null : _message,
          onRefresh: _controller.refresh,
          onStart: () {
            setState(() => _message = null);
            unawaited(_controller.start());
          },
          onLog: (exercise, kg, reps) =>
              unawaited(_controller.logSet(exercise, weightKg: kg, reps: reps)),
          onDeleteSet: (set) => unawaited(_controller.deleteSet(set)),
          onComplete: () => unawaited(_complete(value)),
        ),
        AsyncError(:final error) => ErrorView(
          failure: AppFailure.from(error),
          onRetry: () => unawaited(_controller.retry()),
        ),
        _ => const LoadingView(),
      },
    );
  }
}
