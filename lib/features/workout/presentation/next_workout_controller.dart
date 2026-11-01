import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/entities/next_workout.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_draft.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/usecases/get_level.dart';
import 'package:gym_tracker/features/workout/domain/usecases/get_next_workout.dart';

/// Override in tests: `workoutRepositoryProvider.overrideWithValue(fake)`.
final workoutRepositoryProvider = Provider<WorkoutRepository>(
  (ref) => Dependencies.workoutRepository,
);

/// "Now", injectable so tests can pin dates (missed-day logic).
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// No automatic retry: the repository already retries with backoff, and
/// the error screen has a Try again button.
final nextWorkoutControllerProvider =
    AsyncNotifierProvider<NextWorkoutController, NextWorkout?>(
      NextWorkoutController.new,
      retry: (_, _) => null,
    );

/// The workout waiting for the member; null when they have no plan.
/// Errors carry an `AppFailure`, for `ErrorView`.
class NextWorkoutController extends AsyncNotifier<NextWorkout?> {
  static const _getNext = GetNextWorkout();
  static const _getLevel = GetLevel();

  WorkoutRepository get _repo => ref.read(workoutRepositoryProvider);

  @override
  Future<NextWorkout?> build() async {
    final plan = _unwrap(await _repo.loadPlan());
    if (plan == null || plan.days.isEmpty) return null;
    final history = _unwrap(await _repo.loadHistory());
    final chosen = _unwrap(await _repo.loadChosenDay());
    final now = ref.read(clockProvider)();
    return _getNext(
      plan,
      history,
      now: now,
      chosenDay: chosen,
      level: await _level(history, now),
    );
  }

  /// The level from the history. A new best level is saved (so a comeback
  /// stays fast after old history is trimmed) and counted once; if saving
  /// fails it is worked out again next time.
  Future<LevelProgress> _level(
    List<WorkoutSession> history,
    DateTime now,
  ) async {
    final stored = switch (await _repo.loadBestLevel()) {
      Success(:final value) => value,
      Failed() => Level.beginner,
    };
    final progress = _getLevel(history, now: now, best: stored);
    if (progress.best.index > stored.index &&
        await _repo.saveBestLevel(progress.best) is Success<void>) {
      unawaited(
        Analytics.capture('level_reached', {'level': progress.best.name}),
      );
    }
    return progress;
  }

  Future<void> retry() async {
    ref.invalidateSelf();
    await future.catchError((_) => null);
  }

  /// Saves the ready 5-day plan and shows its first workout.
  Future<void> useTemplate() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      _unwrap(await _repo.savePlan(PlanTemplates.fiveDaySplit));
      unawaited(
        Analytics.capture('plan_created', {
          'source': 'template',
          'days': PlanTemplates.fiveDaySplit.days.length,
        }),
      );
      return await build();
    });
  }

  /// Makes [dayIndex] the next workout (until a workout is finished).
  Future<void> chooseDay(int dayIndex) async {
    state = await AsyncValue.guard(() async {
      _unwrap(await _repo.saveChosenDay(dayIndex));
      unawaited(Analytics.capture('next_day_chosen', {'day': dayIndex + 1}));
      return await build();
    });
  }

  /// Starts the shown workout (or resumes one in progress). Returns false
  /// when it could not be saved.
  Future<bool> startWorkout() async {
    final next = state.value;
    if (next == null) return false;
    final existing = await _repo.loadDraft();
    if (existing case Success(value: final _?)) return true;
    final saved = await _repo.saveDraft(
      WorkoutDraft(
        dayIndex: next.dayIndex,
        startedAt: ref.read(clockProvider)(),
      ),
    );
    if (saved is Failed<void>) return false;
    unawaited(Analytics.capture('workout_started', {'day': next.dayIndex + 1}));
    return true;
  }

  static T _unwrap<T>(Result<T> result) => switch (result) {
    Success(:final value) => value,
    Failed(:final failure) => throw failure,
  };
}
