import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/next_workout.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_draft.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/usecases/get_next_workout.dart';
import 'package:gym_tracker/features/workout/domain/usecases/summarize_workout.dart';
import 'package:gym_tracker/features/workout/domain/usecases/workout_flow.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:meta/meta.dart';

/// Everything the active-workout screen shows.
@immutable
class ActiveWorkout {
  const new({
    required this.day,
    required this.dayIndex,
    required this.totalDays,
    required this.draft,
    required this.previews,
    required this.cursor,
    required this.summary,
  });

  final WorkoutDay day;
  final int dayIndex;
  final int totalDays;
  final WorkoutDraft draft;

  /// Last time and the suggestion, per exercise (same order as [day]).
  final List<ExercisePreview> previews;

  /// The set to do now; null when every planned set is logged.
  final SetCursor? cursor;

  /// Sets, volume and records so far, for the finish sheet.
  final WorkoutSummary summary;

  int get plannedSets => day.totalSets;

  /// Exercises with all their planned sets logged.
  int get exercisesDone => [
    for (final e in day.exercises)
      if (draft.setsFor(e.id).length >= e.targetSets) e,
  ].length;
}

final activeWorkoutControllerProvider =
    AsyncNotifierProvider<ActiveWorkoutController, ActiveWorkout?>(
      ActiveWorkoutController.new,
      retry: (_, _) => null,
    );

/// The workout in progress; null when there is none. Every change is saved
/// to the phone right away.
class ActiveWorkoutController extends AsyncNotifier<ActiveWorkout?> {
  static const _flow = WorkoutFlow();
  static const _summarize = SummarizeWorkout();
  static const _getNext = GetNextWorkout();

  WorkoutRepository get _repo => ref.read(workoutRepositoryProvider);
  DateTime _now() => ref.read(clockProvider)();

  late List<WorkoutSession> _history;
  late WorkoutPlan _plan;

  @override
  Future<ActiveWorkout?> build() async {
    final draft = _unwrap(await _repo.loadDraft());
    if (draft == null) return null;
    final plan = _unwrap(await _repo.loadPlan());
    if (plan == null || plan.dayById(draft.dayId) == null) return null;
    _plan = plan;
    _history = _unwrap(await _repo.loadHistory());
    return _view(draft);
  }

  ActiveWorkout _view(WorkoutDraft draft) {
    final next = _getNext(
      _plan,
      _history,
      now: _now(),
      chosenDay: ChosenDay(draft.dayId),
    );
    return ActiveWorkout(
      day: next.day,
      dayIndex: next.dayIndex,
      totalDays: next.totalDays,
      draft: draft,
      previews: next.exercises,
      cursor: _flow.next(next.day, draft.sets, {
        for (final p in next.exercises) p.exercise.id: p.lastSets,
      }),
      summary: _summarize(
        draft.sets,
        _history,
        startedAt: draft.startedAt,
        now: _now(),
      ),
    );
  }

  Future<void> retry() async {
    ref.invalidateSelf();
    await future.catchError((_) => null);
  }

  /// Logs the current set and starts the rest (none inside a superset round).
  Future<void> logSet({required double weight, required int reps}) async {
    final current = state.value;
    final cursor = current?.cursor;
    if (current == null || cursor == null) return;
    final exercise = current.day.exercises[cursor.exerciseIndex];
    final sets = [
      ...current.draft.sets,
      LoggedSet(
        exerciseId: exercise.id,
        weight: _cleanWeight(weight),
        reps: reps.clamp(0, maxReps),
      ),
    ];
    final allDone = _flow.next(current.day, sets, const {}) == null;
    await _save(
      current.draft.copyWith(
        sets: sets,
        restEndsAt: () => cursor.restAfter > 0 && !allDone
            ? _now().add(Duration(seconds: cursor.restAfter))
            : null,
      ),
    );
  }

  /// Fixes a logged set ([index] in the draft's sets).
  Future<void> editSet(int index, {required double weight, required int reps}) {
    final draft = state.value?.draft;
    if (draft == null || index < 0 || index >= draft.sets.length) {
      return Future.value();
    }
    final sets = [...draft.sets];
    sets[index] = LoggedSet(
      exerciseId: sets[index].exerciseId,
      weight: _cleanWeight(weight),
      reps: reps.clamp(0, maxReps),
    );
    return _save(draft.copyWith(sets: sets));
  }

  Future<void> deleteSet(int index) {
    final draft = state.value?.draft;
    if (draft == null || index < 0 || index >= draft.sets.length) {
      return Future.value();
    }
    return _save(draft.copyWith(sets: [...draft.sets]..removeAt(index)));
  }

  Future<void> addRest(Duration extra) {
    final draft = state.value?.draft;
    final ends = draft?.restEndsAt;
    if (draft == null || ends == null) return Future.value();
    return _save(draft.copyWith(restEndsAt: () => ends.add(extra)));
  }

  Future<void> endRest() {
    final draft = state.value?.draft;
    if (draft == null || draft.restEndsAt == null) return Future.value();
    return _save(draft.copyWith(restEndsAt: () => null));
  }

  /// Saves the workout to history, advances the plan and clears the draft.
  /// Returns false if saving failed (the draft is kept).
  Future<bool> finish() async {
    final current = state.value;
    if (current == null) return false;
    final saved = await _repo.saveSession(
      WorkoutSession(
        dayId: current.day.id,
        finishedAt: _now(),
        sets: current.draft.sets,
      ),
    );
    if (saved is Failed<void>) {
      state = AsyncError(saved.failure, StackTrace.current);
      return false;
    }
    await _repo.saveDraft(null);
    unawaited(
      Analytics.capture('workout_finished', {
        'day': current.dayIndex + 1,
        'sets': current.draft.sets.length,
        'planned_sets': current.plannedSets,
        'minutes': current.summary.duration.inMinutes,
        'records': current.summary.records.length,
      }),
    );
    state = const AsyncData(null);
    ref.invalidate(nextWorkoutControllerProvider);
    return true;
  }

  /// Highest reps accepted per set; anything above is a typo.
  static const maxReps = 999;

  /// Highest weight accepted, kg.
  static const maxWeight = 1000.0;

  static double _cleanWeight(double kg) =>
      kg.isFinite ? kg.clamp(0, maxWeight).toDouble() : 0;

  Future<void> _save(WorkoutDraft draft) async {
    final previous = state.value;
    if (previous != null) state = AsyncData(_view(draft));
    final result = await _repo.saveDraft(draft);
    if (result case Failed(:final failure)) {
      state = AsyncError(failure, StackTrace.current);
    }
  }

  static T _unwrap<T>(Result<T> result) => switch (result) {
    Success(:final value) => value,
    Failed(:final failure) => throw failure,
  };
}
