import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/features/workout/presentation/exercise_history_view.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/progress_controller.dart';

class ExerciseHistoryPage extends ConsumerStatefulWidget {
  const new({required this.exerciseId, super.key});

  /// From the link: untrusted. Unknown ids show "not in your plan".
  final String exerciseId;

  @override
  ConsumerState<ExerciseHistoryPage> createState() =>
      _ExerciseHistoryPageState();
}

class _ExerciseHistoryPageState extends ConsumerState<ExerciseHistoryPage> {
  @override
  void initState() {
    super.initState();
    // No exercise id: it comes from a link, and the event needs no detail.
    unawaited(Analytics.capture('exercise_history_opened'));
  }

  @override
  Widget build(BuildContext context) {
    final provider = exerciseHistoryProvider(widget.exerciseId);
    return ExerciseHistoryView(
      state: ref.watch(provider),
      onRetry: () => ref.invalidate(provider),
      now: ref.read(clockProvider),
    );
  }
}
