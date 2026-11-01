import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/workout/presentation/progress_controller.dart';
import 'package:gym_tracker/features/workout/presentation/progress_view.dart';

class ProgressPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends ConsumerState<ProgressPage> {
  @override
  void initState() {
    super.initState();
    unawaited(Analytics.capture('progress_opened'));
  }

  @override
  Widget build(BuildContext context) => ProgressView(
    state: ref.watch(progressOverviewProvider),
    onRetry: () => ref.invalidate(progressOverviewProvider),
    onOpen: (id) =>
        unawaited(context.push<void>(AppRoutes.exerciseHistory(id))),
  );
}
