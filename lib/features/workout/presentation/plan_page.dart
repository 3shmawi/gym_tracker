import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/workout/presentation/plan_editor_controller.dart';
import 'package:gym_tracker/features/workout/presentation/plan_view.dart';

/// `/plan`: the days of the plan. A new day opens right away, so its
/// exercises can be added.
class PlanPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<PlanPage> createState() => _PlanPageState();
}

class _PlanPageState extends ConsumerState<PlanPage> {
  @override
  void initState() {
    super.initState();
    unawaited(Analytics.capture('plan_opened'));
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.read(planEditorControllerProvider.notifier);
    return PlanView(
      state: ref.watch(planEditorControllerProvider),
      onRetry: () => unawaited(controller.retry()),
      onRetrySave: () => unawaited(controller.retrySave()),
      onOpenDay: (id) => unawaited(context.push<void>(AppRoutes.planDay(id))),
      onAddDay: (name) async {
        final id = await controller.addDay(name);
        if (id != null && context.mounted) {
          await context.push<void>(AppRoutes.planDay(id));
        }
      },
      onRenameDay: (id, name) => unawaited(controller.renameDay(id, name)),
      onDeleteDay: (id) => unawaited(controller.deleteDay(id)),
      onMoveDay: (from, to) => unawaited(controller.moveDay(from, to)),
    );
  }
}
