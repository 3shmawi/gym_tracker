import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_plan.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_plan_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/usecases/edit_plan.dart';

/// Brings the phone's copy of a gym plan up to the server's
/// (docs/decisions/gym_accounts.md §11): **the server's plan wins**.
///
/// - newer `version` → the local plan is replaced;
/// - the workout waiting stays the same ([KeepNextWorkout]: the chosen day is
///   pinned when the history alone would now point elsewhere);
/// - a workout in progress is untouched: the new plan waits (`pending`) and
///   is applied when the workout ends ([applyPending]);
/// - the toast is for a change someone else made, once per version.
class SyncGymPlan {
  const new(
    this._remote,
    this._store,
    this._workouts, {
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final GymPlanRepository _remote;
  final GymPlanStore _store;

  /// Where the active workout state (draft, history, chosen day) lives.
  final WorkoutRepository _workouts;
  static const _keepNext = KeepNextWorkout();
  final DateTime Function() _now;

  Future<Result<PlanSyncOutcome>> call(String membershipId) async {
    final stored = switch (await _store.load(membershipId)) {
      Success(:final value) => value,
      Failed() => null,
    };
    final fetched = await _remote.fetch(membershipId);
    switch (fetched) {
      case Failed(:final failure):
        // Offline (or the server is down): the copy on the phone is the plan.
        if (failure is NetworkFailure || failure is TimeoutFailure) {
          return const Success(PlanSyncOutcome(offline: true));
        }
        return Failed(failure);
      case Success(:final value):
        return await _apply(membershipId, stored, value);
    }
  }

  Future<Result<PlanSyncOutcome>> _apply(
    String membershipId,
    StoredGymPlan? stored,
    GymPlan? remote,
  ) async {
    if (remote == null) {
      // The captain has made no plan (or took it away): nothing to show.
      if (stored != null) await _store.clear(membershipId);
      return Success(PlanSyncOutcome(replaced: stored != null));
    }
    if (stored != null && remote.version <= stored.version) {
      return const Success(PlanSyncOutcome());
    }
    final draft = switch (await _workouts.loadDraft()) {
      Success(:final value) => value,
      Failed() => null,
    };
    final toast =
        remote.changedByOther &&
        remote.version > (stored?.seenVersion ?? 0) &&
        stored != null;
    if (draft != null && stored != null) {
      // A workout is in progress on the old plan: leave everything as it is.
      await _store.save(membershipId, stored.copyWith(pending: () => remote));
      return Success(PlanSyncOutcome(deferred: true, toast: toast));
    }
    return await _replace(membershipId, stored, remote, toast: toast);
  }

  /// Applies a plan that arrived during a workout; call when it ends.
  Future<Result<PlanSyncOutcome>> applyPending(String membershipId) async {
    final stored = switch (await _store.load(membershipId)) {
      Success(:final value) => value,
      Failed() => null,
    };
    final pending = stored?.pending;
    if (stored == null || pending == null) {
      return const Success(PlanSyncOutcome());
    }
    return await _replace(membershipId, stored, pending, toast: false);
  }

  Future<Result<PlanSyncOutcome>> _replace(
    String membershipId,
    StoredGymPlan? stored,
    GymPlan remote, {
    required bool toast,
  }) async {
    final before = stored?.plan;
    final history = switch (await _workouts.loadHistory()) {
      Success(:final value) => value,
      Failed() => const <WorkoutSession>[],
    };
    final chosen = switch (await _workouts.loadChosenDay()) {
      Success(:final value) => value,
      Failed() => null,
    };
    // The waiting workout stays the same across the replacement.
    final pin = before == null
        ? null
        : _keepNext(
            before: before,
            after: remote.plan,
            history: history,
            chosen: chosen,
            now: _now(),
          );
    final saved = await _store.save(
      membershipId,
      StoredGymPlan(
        plan: remote.plan,
        version: remote.version,
        seenVersion: toast ? remote.version : (stored?.seenVersion ?? 0),
      ),
    );
    if (saved case Failed(:final failure)) return Failed(failure);
    if (before != null) await _workouts.saveChosenDay(pin);
    return Success(PlanSyncOutcome(replaced: true, toast: toast));
  }
}
