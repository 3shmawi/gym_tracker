import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_plan.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_plan_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/session_outbox.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';

/// The server's `plans` + `save_plan`, in memory: versions, `plan_changed`
/// when the base version is old, and a "refuse" switch for a revoked right.
class FakePlanServer implements GymPlanRepository {
  GymPlan? plan;
  AppFailure? failFetch;
  AppFailure? failSave;
  int fetches = 0;
  int saves = 0;

  @override
  Future<Result<GymPlan?>> fetch(String membershipId) async {
    fetches++;
    if (failFetch != null) return Failed(failFetch!);
    return Success(plan);
  }

  @override
  Future<Result<GymPlan>> save(
    String membershipId,
    int baseVersion,
    WorkoutPlan next,
  ) async {
    saves++;
    if (failSave != null) return Failed(failSave!);
    final current = plan;
    if ((current?.version ?? 0) != baseVersion) {
      return const Failed(PlanChangedFailure());
    }
    plan = GymPlan(
      membershipId: membershipId,
      plan: next,
      version: baseVersion + 1,
      updatedBy: membershipId,
    );
    return Success(plan!);
  }
}

class MemoryPlanStore implements GymPlanStore {
  final Map<String, StoredGymPlan> data = {};

  @override
  Future<Result<StoredGymPlan?>> load(String membershipId) async =>
      Success(data[membershipId]);

  @override
  Future<Result<void>> save(String membershipId, StoredGymPlan stored) async {
    data[membershipId] = stored;
    return const Success(null);
  }

  @override
  Future<Result<void>> clear(String membershipId) async {
    data.remove(membershipId);
    return const Success(null);
  }
}

class MemoryOutbox implements SessionOutbox {
  final List<OutboxEntry> entries = [];

  @override
  Future<Result<List<OutboxEntry>>> load() async => Success([...entries]);

  @override
  Future<Result<void>> add(OutboxEntry entry) async {
    if (!entries.any((e) => e.clientId == entry.clientId)) entries.add(entry);
    return const Success(null);
  }

  @override
  Future<Result<void>> remove(Set<String> clientIds) async {
    entries.removeWhere((e) => clientIds.contains(e.clientId));
    return const Success(null);
  }
}

/// Stores what it is given; `script` entries `fail` make the next call fail.
class FakeUploader implements SessionUploader {
  final Map<String, OutboxEntry> stored = {};
  final List<String> script = [];
  int calls = 0;
  final List<int> chunkSizes = [];

  @override
  Future<Result<void>> upload(List<OutboxEntry> entries) async {
    calls++;
    chunkSizes.add(entries.length);
    if (script.isNotEmpty && script.removeAt(0) == 'fail') {
      return const Failed(NetworkFailure());
    }
    for (final e in entries) {
      stored.putIfAbsent(e.clientId, () => e);
    }
    return const Success(null);
  }
}

GymPlan gymPlan({
  String membershipId = 'm1',
  int version = 1,
  String? updatedBy,
  WorkoutPlan? plan,
}) => GymPlan(
  membershipId: membershipId,
  plan: plan ?? PlanTemplates.fiveDaySplit,
  version: version,
  updatedBy: updatedBy,
);

/// The template with day 1 renamed, so it differs from [PlanTemplates].
WorkoutPlan renamedDay1() {
  final days = PlanTemplates.fiveDaySplit.days;
  return WorkoutPlan(
    days: [
      WorkoutDay(
        id: days.first.id,
        name: const LocalizedName(ar: 'جديد', en: 'Renamed'),
        exercises: days.first.exercises,
      ),
      ...days.skip(1),
    ],
  );
}

/// [plan] without the day [dayId].
WorkoutPlan planWithout(WorkoutPlan plan, String dayId) => WorkoutPlan(
  days: [
    for (final d in plan.days)
      if (d.id != dayId) d,
  ],
);
