import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/library/presentation/exercise_guide_view.dart';
import 'package:gym_tracker/features/library/presentation/library_providers.dart';
import 'package:gym_tracker/features/library/presentation/widgets/library_feedback.dart';
import 'package:gym_tracker/features/workout/presentation/plan_editor_controller.dart';

/// `/library/<exerciseId>[?day=<dayId>]`: the picture and steps of one
/// exercise. With a day it offers to add the exercise to it. Both ids are
/// untrusted: an unknown exercise says "not in the library", an unknown day
/// just hides the add button.
class ExerciseGuidePage extends ConsumerStatefulWidget {
  const new({required this.exerciseId, this.dayId, super.key});

  final String exerciseId;
  final String? dayId;

  @override
  ConsumerState<ExerciseGuidePage> createState() => _ExerciseGuidePageState();
}

class _ExerciseGuidePageState extends ConsumerState<ExerciseGuidePage> {
  @override
  void initState() {
    super.initState();
    final muscle = ref
        .read(exerciseLibraryProvider)
        .byId(widget.exerciseId)
        ?.muscle
        .name;
    unawaited(
      Analytics.capture('library_exercise_viewed', {'muscle': ?muscle}),
    );
  }

  Future<void> _add(String dayId) async {
    final exercise = ref.read(exerciseLibraryProvider).byId(widget.exerciseId);
    if (exercise == null) return;
    final error = await ref
        .read(planEditorControllerProvider.notifier)
        .addLibraryExercise(dayId, exercise.defaults);
    if (!mounted) return;
    if (error != null) {
      showPlanEditError(context, error);
      return;
    }
    if (context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final exercise = ref.watch(exerciseLibraryProvider).byId(widget.exerciseId);
    final dayId = widget.dayId;
    final lang = Localizations.localeOf(context).languageCode;
    final editor = dayId == null
        ? null
        : ref.watch(planEditorControllerProvider).value;
    final day = dayId == null ? null : editor?.plan.dayById(dayId);
    final canAdd = day != null && (editor?.permissions.editStructure ?? false);
    return ExerciseGuideView(
      exercise: exercise,
      onBack: () => context.go(AppRoutes.plan),
      dayName: canAdd ? day.name.of(lang) : null,
      alreadyInDay:
          day?.exercises.any((e) => e.id == widget.exerciseId) ?? false,
      onAdd: canAdd ? () => unawaited(_add(day.id)) : null,
    );
  }
}
