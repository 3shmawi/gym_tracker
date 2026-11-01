import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/workout/domain/entities/next_workout.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/log_panel.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/rest_panel.dart';
import 'package:gym_tracker/features/workout/presentation/workout_format.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// Callbacks of the active-workout screen.
class ActiveWorkoutActions {
  const new({
    required this.onLog,
    required this.onEditSet,
    required this.onDeleteSet,
    required this.onAdd15,
    required this.onEndRest,
    required this.onFinish,
    required this.onClose,
    required this.onRetry,
  });

  final void Function(double weight, int reps) onLog;

  /// `index` is the set's position in the workout's logged sets.
  final void Function(int index, double weight, int reps) onEditSet;
  final void Function(int index) onDeleteSet;
  final VoidCallback onAdd15;
  final VoidCallback onEndRest;
  final Future<void> Function() onFinish;
  final VoidCallback onClose;
  final VoidCallback onRetry;
}

/// The workout in progress. One list (done exercises collapsed, the current
/// one expanded) and a dock in the thumb zone that logs, rests or finishes.
/// Data + callbacks only; `ActiveWorkoutPage` wires it.
class ActiveWorkoutView extends StatelessWidget {
  const new({
    required this.state,
    required this.actions,
    required this.now,
    super.key,
  });

  /// null value: no workout in progress.
  final AsyncValue<ActiveWorkout?> state;
  final ActiveWorkoutActions actions;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final workout = state.value;
    return AppScaffold(
      title: workout?.day.name.of(lang),
      // Close (the workout stays saved) replaces back, as in the design:
      // two buttons doing the same thing crowded the bar.
      leading: AppIconButton(
        key: const Key('workout_close'),
        tooltip: l10n.workoutClose,
        icon: Icons.close,
        onPressed: actions.onClose,
      ),
      // The dock pads itself, so its surface reaches the bottom edge.
      padBottom: !(state is AsyncData && workout != null),
      actions: [
        if (workout != null)
          AppIconButton(
            key: const Key('workout_finish_menu'),
            tooltip: l10n.workoutFinish,
            icon: Icons.flag_outlined,
            onPressed: () => _showFinish(context, workout),
          ),
      ],
      body: switch (state) {
        AsyncData(value: final w?) => _Workout(
          workout: w,
          actions: actions,
          now: now,
          onFinish: () => _showFinish(context, w),
        ),
        AsyncData() => EmptyView(
          icon: Icons.fitness_center,
          message: l10n.workoutNone,
          action: AppPrimaryButton(
            key: const Key('workout_go_home'),
            label: l10n.workoutGoHome,
            onPressed: actions.onClose,
          ),
        ),
        AsyncError(:final error) => ErrorView(
          failure: error is AppFailure ? error : UnknownFailure(error),
          onRetry: actions.onRetry,
        ),
        _ => const LoadingView(),
      },
    );
  }

  Future<void> _showFinish(BuildContext context, ActiveWorkout w) async {
    final finish = await showAppSheet<bool>(
      context: context,
      builder: (sheet) => _FinishSheet(workout: w),
    );
    if (finish ?? false) await actions.onFinish();
  }
}

class _Workout extends StatefulWidget {
  const new({
    required this.workout,
    required this.actions,
    required this.now,
    required this.onFinish,
  });

  final ActiveWorkout workout;
  final ActiveWorkoutActions actions;
  final DateTime Function() now;
  final VoidCallback onFinish;

  @override
  State<_Workout> createState() => _WorkoutState();
}

/// Keeps the current exercise at the top of the list: after each set the
/// finished ones scroll away, so a superset's A and B are both in view.
class _WorkoutState extends State<_Workout> {
  final GlobalKey _currentKey = GlobalKey();

  ActiveWorkout get workout => widget.workout;
  ActiveWorkoutActions get actions => widget.actions;
  DateTime Function() get now => widget.now;
  VoidCallback get onFinish => widget.onFinish;

  @override
  void initState() {
    super.initState();
    _scrollToCurrent(animate: false);
  }

  @override
  void didUpdateWidget(_Workout old) {
    super.didUpdateWidget(old);
    if (old.workout.cursor?.exerciseIndex != workout.cursor?.exerciseIndex) {
      _scrollToCurrent(animate: true);
    }
  }

  void _scrollToCurrent({required bool animate}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _currentKey.currentContext;
      if (!mounted || target == null) return;
      final reduceMotion = MediaQuery.disableAnimationsOf(context);
      Scrollable.ensureVisible(
        target,
        duration: animate && !reduceMotion
            ? const Duration(milliseconds: 260)
            : Duration.zero,
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final cursor = workout.cursor;
    final exercises = workout.day.exercises;
    final current = cursor?.exerciseIndex;
    final partner = cursor?.supersetPartner;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsetsDirectional.symmetric(
            horizontal: AppDimens.md,
            vertical: AppDimens.xs,
          ),
          child: AppSegmentedProgress(
            total: exercises.length,
            current: workout.exercisesDone.toDouble(),
            semanticLabel: l10n.workoutExercisesDone(
              workout.exercisesDone,
              exercises.length,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            // Build every row so the current one can always be scrolled to.
            scrollCacheExtent: const ScrollCacheExtent.pixels(10000),
            padding: EdgeInsets.all(AppDimens.md),
            children: [
              for (final (i, preview) in workout.previews.indexed)
                Padding(
                  key: i == current ? _currentKey : null,
                  padding: EdgeInsetsDirectional.only(bottom: AppDimens.sm),
                  child: i == current || i == partner
                      ? _CurrentExercise(
                          number: i + 1,
                          preview: preview,
                          workout: workout,
                          isNow: i == current,
                          onEditSet: (index) => _edit(context, index),
                        )
                      : _ExerciseLine(
                          number: i + 1,
                          preview: preview,
                          logged: workout.draft.setsFor(preview.exercise.id),
                        ),
                ),
            ],
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.surfaceSolid,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppDimens.radiusSheet),
            ),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.all(AppDimens.md),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _dock(context),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _dock(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final cursor = workout.cursor;
    final restEnds = workout.draft.restEndsAt;
    if (cursor == null) {
      return Column(
        key: const ValueKey('done'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppDimens.sm2,
        children: [
          Text(
            l10n.workoutAllDone,
            textAlign: TextAlign.center,
            style: AppTextStyles.title.copyWith(
              color: context.palette.textPrimary,
            ),
          ),
          AppPrimaryButton(
            key: const Key('finish_button'),
            icon: Icons.flag,
            label: l10n.workoutFinish,
            onPressed: onFinish,
          ),
        ],
      );
    }
    final exercise = workout.day.exercises[cursor.exerciseIndex];
    if (restEnds != null && restEnds.isAfter(now())) {
      final last = workout.draft.sets.lastOrNull;
      final lastExercise = workout.day.exercises
          .where((e) => e.id == last?.exerciseId)
          .firstOrNull;
      return RestPanel(
        key: ValueKey('rest-${workout.draft.sets.length}'),
        endsAt: restEnds,
        totalSeconds: lastExercise?.restSeconds ?? exercise.restSeconds,
        now: now,
        nextLabel: l10n.workoutNext(
          exercise.name.of(lang),
          WorkoutFormat.weightTimesReps(cursor.weight, cursor.reps),
        ),
        onAdd15: actions.onAdd15,
        onSkip: actions.onEndRest,
        onRestOver: actions.onEndRest,
      );
    }
    final partner = cursor.supersetPartner;
    return LogPanel(
      key: ValueKey(
        'log-${cursor.exerciseIndex}-${cursor.setNumber}-'
        '${workout.draft.sets.length}',
      ),
      setNumber: cursor.setNumber,
      totalSets: exercise.targetSets,
      targetReps: exercise.targetReps,
      weight: cursor.weight,
      reps: cursor.reps,
      weightStep: exercise.weightStep,
      partnerName: partner != null && cursor.restAfter == 0
          ? workout.day.exercises[partner].name.of(lang)
          : null,
      onLog: actions.onLog,
    );
  }

  Future<void> _edit(BuildContext context, int index) async {
    final set = workout.draft.sets[index];
    final exercise = workout.day.exercises.firstWhere(
      (e) => e.id == set.exerciseId,
    );
    final number = workout.draft.sets
        .take(index + 1)
        .where((s) => s.exerciseId == set.exerciseId)
        .length;
    final result = await showAppSheet<_EditResult>(
      context: context,
      builder: (_) => _EditSetSheet(
        setNumber: number,
        weight: set.weight,
        reps: set.reps,
        weightStep: exercise.weightStep,
      ),
    );
    switch (result) {
      case _EditResult(delete: true):
        actions.onDeleteSet(index);
      case _EditResult(:final weight, :final reps):
        actions.onEditSet(index, weight, reps);
      case null:
        break;
    }
  }
}

/// A done or upcoming exercise: one line.
class _ExerciseLine extends StatelessWidget {
  const new({
    required this.number,
    required this.preview,
    required this.logged,
  });

  final int number;
  final ExercisePreview preview;
  final List<LoggedSet> logged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final lang = Localizations.localeOf(context).languageCode;
    final exercise = preview.exercise;
    final done = logged.length >= exercise.targetSets;
    final weight = preview.suggestion.weight;
    return MergeSemantics(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppDimens.minTouchTarget),
        child: Padding(
          padding: EdgeInsetsDirectional.symmetric(horizontal: AppDimens.xs),
          child: Row(
            spacing: AppDimens.sm2,
            children: [
              _NumberDot(number: number, done: done),
              Expanded(
                child: Text(
                  exercise.name.of(lang),
                  style: AppTextStyles.body.copyWith(
                    color: done ? palette.textPrimary : palette.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (done)
                Text(
                  WorkoutFormat.ltr(WorkoutFormat.sets(logged)),
                  style: AppTextStyles.caption.copyWith(
                    color: palette.textSecondary,
                  ),
                )
              else if (weight != null)
                Text(
                  WorkoutFormat.ltr(WorkoutFormat.weight(weight)),
                  style: AppTextStyles.label.copyWith(
                    color: palette.textSecondary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberDot extends StatelessWidget {
  const new({required this.number, required this.done});

  final int number;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: done ? scheme.primary : palette.fillSubtle,
        shape: BoxShape.circle,
      ),
      child: done
          ? Icon(Icons.check, size: 16, color: scheme.onPrimary)
          : Text(
              '$number',
              style: AppTextStyles.label.copyWith(color: palette.textSecondary),
            ),
    );
  }
}

/// The exercise being done (and its superset partner): name, last time,
/// trend, and a chip per set. Logged chips open the edit sheet.
class _CurrentExercise extends StatelessWidget {
  const new({
    required this.number,
    required this.preview,
    required this.workout,
    required this.isNow,
    required this.onEditSet,
  });

  final int number;
  final ExercisePreview preview;
  final ActiveWorkout workout;
  final bool isNow;
  final ValueChanged<int> onEditSet;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final lang = Localizations.localeOf(context).languageCode;
    final exercise = preview.exercise;
    final indexes = [
      for (final (i, s) in workout.draft.sets.indexed)
        if (s.exerciseId == exercise.id) i,
    ];
    final total = indexes.length > exercise.targetSets
        ? indexes.length
        : exercise.targetSets;
    final nowSet = isNow ? workout.cursor?.setNumber : null;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppDimens.xs,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppDimens.sm2,
            children: [
              _NumberDot(number: number, done: false),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      exercise.name.of(lang),
                      style: AppTextStyles.headline.copyWith(
                        color: palette.textPrimary,
                        height: 1.2,
                      ),
                    ),
                    Text(
                      exercise.name.other(lang),
                      style: AppTextStyles.caption.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              AppBadge(
                label: switch (preview.suggestion.trend) {
                  Trend.up => l10n.trendUp,
                  Trend.keep => l10n.trendKeep,
                  Trend.down => l10n.trendDown,
                  Trend.firstTime => l10n.trendFirstTime,
                },
                tone: switch (preview.suggestion.trend) {
                  Trend.up => AppTone.up,
                  Trend.keep => AppTone.keep,
                  Trend.down => AppTone.down,
                  Trend.firstTime => AppTone.fresh,
                },
              ),
            ],
          ),
          if (workout.cursor?.supersetPartner != null)
            Row(
              spacing: AppDimens.xs,
              children: [
                Icon(
                  Icons.swap_vert,
                  size: MediaQuery.textScalerOf(context).scale(16),
                  color: Theme.of(context).colorScheme.primary,
                ),
                Flexible(
                  child: Text(
                    l10n.workoutSupersetLabel,
                    style: AppTextStyles.caption.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          if (preview.lastSets.isNotEmpty)
            Text(
              l10n.exerciseLast(
                WorkoutFormat.ltr(WorkoutFormat.sets(preview.lastSets)),
              ),
              style: AppTextStyles.caption.copyWith(
                color: palette.textSecondary,
              ),
            ),
          Wrap(
            spacing: AppDimens.xs + 2,
            children: [
              for (var n = 1; n <= total; n++)
                if (n <= indexes.length)
                  () {
                    final set = workout.draft.sets[indexes[n - 1]];
                    final w = WorkoutFormat.weight(set.weight);
                    return AppSetChip(
                      key: Key('set_chip_${exercise.id}_$n'),
                      label: '$w×${set.reps}',
                      state: AppSetState.done,
                      semanticLabel: l10n.workoutSetDoneLabel(n, w, set.reps),
                      onTap: () => onEditSet(indexes[n - 1]),
                    );
                  }()
                else
                  AppSetChip(
                    label: n == nowSet ? l10n.workoutSetChip(n) : '$n',
                    state: n == nowSet
                        ? AppSetState.current
                        : AppSetState.pending,
                    semanticLabel: n == nowSet
                        ? l10n.workoutSetNowLabel(n)
                        : l10n.workoutSetLaterLabel(n),
                  ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditResult {
  const new({required this.weight, required this.reps, this.delete = false});

  final double weight;
  final int reps;
  final bool delete;
}

class _EditSetSheet extends StatefulWidget {
  const new({
    required this.setNumber,
    required this.weight,
    required this.reps,
    required this.weightStep,
  });

  final int setNumber;
  final double weight;
  final int reps;
  final double weightStep;

  @override
  State<_EditSetSheet> createState() => _EditSetSheetState();
}

class _EditSetSheetState extends State<_EditSetSheet> {
  late double _weight = widget.weight;
  late int _reps = widget.reps;
  bool _confirmDelete = false;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppDimens.md,
        0,
        AppDimens.md,
        AppDimens.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppDimens.sm2,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.workoutEditSet(widget.setNumber),
              style: AppTextStyles.title.copyWith(color: palette.textPrimary),
            ),
          ),
          SetSteppers(
            weight: _weight,
            reps: _reps,
            weightStep: widget.weightStep,
            onWeight: (w) => setState(() => _weight = w),
            onReps: (r) => setState(() => _reps = r),
          ),
          AppPrimaryButton(
            key: const Key('edit_save'),
            label: l10n.workoutSave,
            onPressed: () =>
                Navigator.of(context)
                    .pop(_EditResult(weight: _weight, reps: _reps)),
          ),
          AppSecondaryButton(
            key: const Key('edit_delete'),
            icon: Icons.delete_outline,
            label: _confirmDelete
                ? l10n.workoutDeleteConfirm
                : l10n.workoutDeleteSet,
            onPressed: () {
              if (_confirmDelete) {
                Navigator.of(
                  context,
                ).pop(_EditResult(weight: _weight, reps: _reps, delete: true));
              } else {
                setState(() => _confirmDelete = true);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Confirmation and a short summary in one sheet: sets, volume, records.
class _FinishSheet extends StatelessWidget {
  const new({required this.workout});

  final ActiveWorkout workout;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final lang = Localizations.localeOf(context).languageCode;
    final summary = workout.summary;
    final left = workout.plannedSets - summary.sets;
    final names = {
      for (final e in workout.day.exercises) e.id: e.name.of(lang),
    };

    Widget stat(String label, String value, {Color? color}) => Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.fillSubtle,
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        ),
        child: Padding(
          padding: EdgeInsets.all(AppDimens.sm2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 2,
            children: [
              Text(
                label,
                style: AppTextStyles.caption.copyWith(
                  color: palette.textSecondary,
                ),
              ),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Text(
                  value,
                  style: AppTextStyles.numL.copyWith(
                    color: color ?? palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppDimens.md,
        0,
        AppDimens.md,
        AppDimens.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppDimens.sm2,
        children: [
          Semantics(
            header: true,
            child: Text(
              left > 0
                  ? l10n.workoutSetsLeft(left)
                  : l10n.workoutDoneTitle(workout.day.name.of(lang)),
              textAlign: TextAlign.center,
              style: AppTextStyles.headline.copyWith(
                color: palette.textPrimary,
              ),
            ),
          ),
          Text(
            '${l10n.todayDayOf(workout.dayIndex + 1, workout.totalDays)} · '
            '${l10n.workoutMinutes(summary.duration.inMinutes)}',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(color: palette.textSecondary),
          ),
          Row(
            spacing: AppDimens.sm,
            children: [
              stat(
                l10n.workoutStatSets,
                '${summary.sets}/${workout.plannedSets}',
              ),
              stat(
                l10n.workoutStatVolume,
                WorkoutFormat.weight(summary.volume),
              ),
              stat(
                l10n.workoutStatRecords,
                '${summary.records.length}',
                color: summary.records.isEmpty ? null : palette.trendUp,
              ),
            ],
          ),
          for (final r in summary.records)
            Row(
              spacing: AppDimens.sm,
              children: [
                AppBadge(label: l10n.workoutRecord, tone: AppTone.up),
                Expanded(
                  child: Text(
                    names[r.exerciseId] ?? r.exerciseId,
                    style: AppTextStyles.body.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                Text(
                  WorkoutFormat.ltr(
                    '${WorkoutFormat.weight(r.weight)}×${r.reps}',
                  ),
                  style: AppTextStyles.label.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ],
            ),
          AppPrimaryButton(
            key: const Key('finish_confirm'),
            icon: Icons.flag,
            label: left > 0 ? l10n.workoutFinishAnyway : l10n.workoutFinish,
            onPressed: () => Navigator.of(context).pop(true),
          ),
          AppSecondaryButton(
            key: const Key('finish_keep_going'),
            label: l10n.workoutKeepGoing,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }
}
