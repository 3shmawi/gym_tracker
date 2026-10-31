import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/usecases/suggest_next_weight.dart';

/// Override in tests: `workoutRepositoryProvider.overrideWithValue(fake)`.
final workoutRepositoryProvider = Provider<WorkoutRepository>(
  (ref) => Dependencies.workoutRepository,
);

final workoutControllerProvider =
    AsyncNotifierProvider<WorkoutController, WorkoutState>(
      WorkoutController.new,
      // The error view has its own retry button.
      retry: (_, _) => null,
    );

/// Number of writes not on the server yet (shown as "saved on this phone").
final workoutPendingSyncProvider = StreamProvider<int>(
  (ref) => ref.watch(workoutRepositoryProvider).watchPendingCount(),
);

@immutable
class WorkoutState {
  const new({
    required this.plan,
    this.session,
    this.sessionSets = const [],
    this.lastSets = const {},
    this.refreshFailure,
  });

  final AssignedPlan? plan;

  /// The workout in progress, if started.
  final WorkoutSession? session;
  final List<LoggedSet> sessionSets;

  /// Sets of the last completed session, by exercise id.
  final Map<String, List<LoggedSet>> lastSets;

  /// The last refresh failed (the cached plan is still shown).
  final AppFailure? refreshFailure;

  /// The day on screen: the open session's day, else the plan's next day.
  PlanDay? get day {
    final plan = this.plan;
    if (plan == null) return null;
    final sessionDayId = session?.planDayId;
    if (sessionDayId != null) {
      for (final d in plan.days) {
        if (d.id == sessionDayId) return d;
      }
    }
    return plan.nextDay;
  }

  bool get isActive => session != null;

  List<LoggedSet> setsFor(String exerciseId) =>
      sessionSets.where((s) => s.exerciseId == exerciseId).toList();

  WeightSuggestion suggestionFor(PlanExercise exercise) =>
      const SuggestNextWeight()(
        exercise: exercise,
        lastSession: lastSets[exercise.exerciseId] ?? const [],
      );

  /// All planned sets of the day are logged.
  bool get allSetsLogged {
    final day = this.day;
    if (day == null) return false;
    return day.exercises.every((e) => setsFor(e.exerciseId).length >= e.sets);
  }

  WorkoutState copyWith({
    AssignedPlan? plan,
    ValueGetter<WorkoutSession?>? session,
    List<LoggedSet>? sessionSets,
    Map<String, List<LoggedSet>>? lastSets,
    ValueGetter<AppFailure?>? refreshFailure,
  }) => WorkoutState(
    plan: plan ?? this.plan,
    session: session != null ? session() : this.session,
    sessionSets: sessionSets ?? this.sessionSets,
    lastSets: lastSets ?? this.lastSets,
    refreshFailure: refreshFailure != null
        ? refreshFailure()
        : this.refreshFailure,
  );
}

/// The workout screen's state: next day, open session, logged sets.
/// Everything is read from the device first, so the screen works offline.
class WorkoutController extends AsyncNotifier<WorkoutState> {
  late WorkoutRepository _repo;

  @override
  Future<WorkoutState> build() async {
    _repo = ref.watch(workoutRepositoryProvider);
    final cached = await _repo.cachedPlan();
    if (cached == null) {
      // First launch: nothing on the device yet, so wait for the server.
      final result = await _repo.refreshPlan();
      // AppFailure is the app's error type; the page maps it back.
      // ignore: only_throw_errors
      if (result case Failed(:final failure)) throw failure;
      return await _load((result as Success<AssignedPlan?>).value);
    }
    unawaited(Future(refresh));
    return await _load(cached);
  }

  Future<WorkoutState> _load(
    AssignedPlan? plan, {
    AppFailure? refreshFailure,
  }) async {
    final session = await _repo.openSession();
    final ids = [
      for (final day in plan?.days ?? const <PlanDay>[])
        for (final e in day.exercises) e.exerciseId,
    ];
    return WorkoutState(
      plan: plan,
      session: session,
      sessionSets: session == null ? const [] : await _repo.setsOf(session.id),
      lastSets: await _repo.lastSets(ids),
      refreshFailure: refreshFailure,
    );
  }

  /// Pulls the latest plan (pushing offline changes first). On failure the
  /// cached plan stays on screen.
  Future<void> refresh() async {
    if (!ref.mounted) return;
    final result = await _repo.refreshPlan();
    if (!ref.mounted) return;
    switch (result) {
      case Success(:final value):
        final loaded = await _load(value);
        if (ref.mounted) state = AsyncData(loaded);
      case Failed(:final failure):
        final current = state.value;
        if (current == null) {
          state = AsyncError(failure, StackTrace.current);
        } else {
          state = AsyncData(current.copyWith(refreshFailure: () => failure));
        }
    }
  }

  /// Retries after the first load failed.
  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> start() async {
    final current = state.value;
    final day = current?.day;
    if (current == null || day == null || current.isActive) return;
    final session = await _repo.startSession(day);
    state = AsyncData(current.copyWith(session: () => session));
  }

  Future<LoggedSet?> logSet(
    PlanExercise exercise, {
    required double weightKg,
    required int reps,
  }) async {
    final current = state.value;
    final session = current?.session;
    if (current == null || session == null) return null;
    final set = await _repo.logSet(
      sessionId: session.id,
      exerciseId: exercise.exerciseId,
      setNumber: current.setsFor(exercise.exerciseId).length + 1,
      weightKg: weightKg,
      reps: reps,
    );
    state = AsyncData(
      current.copyWith(sessionSets: [...current.sessionSets, set]),
    );
    unawaited(_repo.sync());
    return set;
  }

  Future<void> deleteSet(LoggedSet set) async {
    final current = state.value;
    if (current == null) return;
    await _repo.deleteSet(set.id);
    state = AsyncData(
      current.copyWith(
        sessionSets: current.sessionSets.where((s) => s.id != set.id).toList(),
      ),
    );
    unawaited(_repo.sync());
  }

  /// Completes the workout; returns the next day.
  Future<PlanDay?> complete() async {
    final session = state.value?.session;
    if (session == null) return null;
    final plan = await _repo.completeSession(session.id);
    state = AsyncData(await _load(plan));
    unawaited(_repo.sync());
    return plan?.nextDay;
  }
}
