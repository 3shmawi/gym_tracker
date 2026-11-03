import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_plan.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_plan_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/session_outbox.dart';
import 'package:gym_tracker/features/gym/domain/usecases/sync_gym_plan.dart';
import 'package:gym_tracker/features/gym/domain/usecases/upload_sessions.dart';
import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_draft.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';

/// The workout repository while the active workspace is a gym
/// (docs/decisions/gym_accounts.md §10): the plan comes from the gym (a copy
/// on the phone, refreshed by `SyncGymPlan`), saving it goes to the server,
/// and every finished workout is also queued for upload. History, the chosen
/// day, the workout in progress and the level stay in [inner]: they are the
/// person's, in any workspace.
class GymWorkoutRepository implements WorkoutRepository {
  const new({
    required this.inner,
    required this.remote,
    required this.store,
    required this.outbox,
    required this.membership,
  });

  final WorkoutRepository inner;
  final GymPlanRepository remote;
  final GymPlanStore store;
  final SessionOutbox outbox;
  final Membership membership;

  String get _id => membership.id;

  Future<StoredGymPlan?> _stored() async => switch (await store.load(_id)) {
    Success(:final value) => value,
    Failed() => null,
  };

  @override
  Future<Result<WorkoutPlan?>> loadPlan() async {
    var stored = await _stored();
    if (stored == null) {
      // First time in this gym: ask now (offline simply leaves no plan).
      await SyncGymPlan(remote, store, inner)(_id);
      stored = await _stored();
    }
    return Success(stored?.plan);
  }

  @override
  Future<Result<void>> savePlan(WorkoutPlan plan) async {
    if (!PlanPermissions.of(membership).canSave) {
      return const Failed(UnauthorizedFailure());
    }
    final base = (await _stored())?.version ?? 0;
    final saved = await remote.save(_id, base, plan);
    switch (saved) {
      case Success(:final value):
        return await store.save(
          _id,
          StoredGymPlan(
            plan: plan,
            version: value.version,
            seenVersion: value.version,
          ),
        );
      case Failed(:final failure):
        // The captain got there first: take their plan (the editor reloads).
        if (failure is PlanChangedFailure) {
          await SyncGymPlan(remote, store, inner)(_id);
        }
        return Failed(failure);
    }
  }

  @override
  Future<Result<void>> saveSession(WorkoutSession session) async {
    final tagged = WorkoutSession(
      dayId: session.dayId,
      finishedAt: session.finishedAt,
      sets: session.sets,
      membershipId: _id,
      startedAt: session.startedAt,
    );
    final saved = await inner.saveSession(tagged);
    if (saved is Success<void>) {
      // A failed queue write is not the member's problem: the workout is
      // saved on the phone either way.
      await QueueSession(outbox)(
        tagged,
        gymId: membership.gym.id,
        membershipId: _id,
      );
    }
    return saved;
  }

  @override
  Future<Result<List<WorkoutSession>>> loadHistory() => inner.loadHistory();

  @override
  Future<Result<ChosenDay?>> loadChosenDay() => inner.loadChosenDay();

  @override
  Future<Result<void>> saveChosenDay(ChosenDay? day) =>
      inner.saveChosenDay(day);

  @override
  Future<Result<WorkoutDraft?>> loadDraft() => inner.loadDraft();

  @override
  Future<Result<void>> saveDraft(WorkoutDraft? draft) => inner.saveDraft(draft);

  @override
  Future<Result<Level>> loadBestLevel() => inner.loadBestLevel();

  @override
  Future<Result<void>> saveBestLevel(Level level) => inner.saveBestLevel(level);

  @override
  Future<Result<void>> clearHistory() => inner.clearHistory();
}
