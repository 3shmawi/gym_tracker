import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/media/cloudinary_url.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/gym/presentation/gym_sync.dart';
import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/features/library/domain/usecases/search_exercises.dart';
import 'package:gym_tracker/features/library/presentation/library_providers.dart';
import 'package:gym_tracker/features/library/presentation/library_view.dart';
import 'package:gym_tracker/features/library/presentation/widgets/library_feedback.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/presentation/plan_editor_controller.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/plan_widgets.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// `/library?day=<dayId>`: pick an exercise for a plan day. A day that isn't
/// in the plan (an old or crafted link) says so; so does a member whose gym
/// keeps the exercises to the captain.
class LibraryPage extends ConsumerStatefulWidget {
  const new({required this.dayId, super.key});

  /// Untrusted: only ever compared with the ids of the member's own plan.
  final String? dayId;

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  static const _search = SearchExercises();

  String _query = '';
  MuscleGroup? _muscle;
  Equipment? _equipment;

  @override
  void initState() {
    super.initState();
    unawaited(Analytics.capture('library_opened'));
  }

  Future<void> _add(String id, String dayId) async {
    final exercise = ref.read(exerciseLibraryProvider).byId(id);
    if (exercise == null) return;
    final error = await ref
        .read(planEditorControllerProvider.notifier)
        .addLibraryExercise(dayId, exercise.defaults);
    if (!mounted || error == null) return;
    showPlanEditError(context, error);
  }

  void _writeOwn(String query, String dayId) {
    unawaited(Analytics.capture('library_custom_chosen'));
    unawaited(
      askName(
        context,
        title: context.l10n.planAddExercise,
        confirmLabel: context.l10n.planAdd,
        initial: query.trim().isEmpty
            ? null
            : LocalizedName(ar: query, en: query),
        onName: (name) async {
          final id = await ref
              .read(planEditorControllerProvider.notifier)
              .addExercise(dayId, name);
          if (id != null && mounted && context.canPop()) context.pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final dayId = widget.dayId;
    final editor = ref.watch(planEditorControllerProvider);
    final plan = editor.value?.plan;
    final day = dayId == null ? null : plan?.dayById(dayId);
    if (editor.isLoading || editor.hasError || day == null) {
      return AppScaffold(
        title: l10n.libraryTitle,
        body: switch (editor) {
          AsyncLoading() => const LoadingView(),
          AsyncError(:final error) => ErrorView(
            failure: error is AppFailure ? error : UnknownFailure(error),
            onRetry: () => ref.invalidate(planEditorControllerProvider),
          ),
          _ => EmptyView(
            icon: Icons.search_off,
            message: l10n.planDayNotFound,
            action: AppSecondaryButton(
              label: l10n.planBackToPlan,
              onPressed: () => context.go(AppRoutes.plan),
            ),
          ),
        },
      );
    }
    final permissions = editor.requireValue.permissions;
    if (!permissions.editStructure) {
      return AppScaffold(
        title: l10n.libraryTitle,
        body: EmptyView(
          icon: Icons.lock_outline,
          message: l10n.planManagedTitle,
          detail: l10n.libraryNotAllowed,
          action: AppSecondaryButton(
            label: l10n.planBackToPlan,
            onPressed: () => context.go(AppRoutes.plan),
          ),
        ),
      );
    }
    final all = ref.watch(exerciseLibraryProvider).all;
    final media = ref.watch(activeGymMediaProvider).value;
    final toImage = ref.watch(gymPictureImageProvider);
    // Each exercise's cover (the gym's first picture) as its row tile.
    final covers = <String, ImageProvider>{
      if (media != null)
        for (final e in all)
          if (media.picturesFor(e.id).firstOrNull case final first?)
            e.id: ?toImage(first.publicId, PictureSize.thumb),
    };
    return LibraryView(
      gymCovers: covers,
      exercises: _search(
        all,
        query: _query,
        muscle: _muscle,
        equipment: _equipment,
      ),
      query: _query,
      muscle: _muscle,
      equipment: _equipment,
      addedIds: {for (final e in day.exercises) e.id},
      dayName: day.name.of(lang),
      onQueryChanged: (q) => setState(() => _query = q),
      onMuscle: (m) => setState(() => _muscle = m),
      onEquipment: (e) => setState(() => _equipment = e),
      onOpen: (id) => unawaited(
        context.push<void>(AppRoutes.libraryExercise(id, dayId: day.id)),
      ),
      onAdd: (id) => unawaited(_add(id, day.id)),
      onWriteOwn: (q) => _writeOwn(q, day.id),
    );
  }
}
