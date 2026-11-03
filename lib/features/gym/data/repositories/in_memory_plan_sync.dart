import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_plan.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_plan_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/session_outbox.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';

/// Used until `Dependencies.init` runs, in widget tests and when the env file
/// has no Supabase values: there is no server, so the phone's copy is the plan.
class UnconfiguredGymPlanRepository implements GymPlanRepository {
  const new();

  @override
  Future<Result<GymPlan?>> fetch(String membershipId) async =>
      const Failed(NetworkFailure());

  @override
  Future<Result<GymPlan>> save(
    String membershipId,
    int baseVersion,
    WorkoutPlan plan,
  ) async => const Failed(NetworkFailure());
}

class UnconfiguredSessionUploader implements SessionUploader {
  const new();

  @override
  Future<Result<void>> upload(List<OutboxEntry> entries) async =>
      const Failed(NetworkFailure());
}

/// Memory only: the default before `Dependencies.init`, and for tests.
class InMemoryGymPlanStore implements GymPlanStore {
  final Map<String, StoredGymPlan> _data = {};

  @override
  Future<Result<StoredGymPlan?>> load(String membershipId) async =>
      Success(_data[membershipId]);

  @override
  Future<Result<void>> save(String membershipId, StoredGymPlan stored) async {
    _data[membershipId] = stored;
    return const Success(null);
  }

  @override
  Future<Result<void>> clear(String membershipId) async {
    _data.remove(membershipId);
    return const Success(null);
  }
}

class InMemorySessionOutbox implements SessionOutbox {
  final List<OutboxEntry> _entries = [];

  @override
  Future<Result<List<OutboxEntry>>> load() async => Success([..._entries]);

  @override
  Future<Result<void>> add(OutboxEntry entry) async {
    if (!_entries.any((e) => e.clientId == entry.clientId)) _entries.add(entry);
    return const Success(null);
  }

  @override
  Future<Result<void>> remove(Set<String> clientIds) async {
    _entries.removeWhere((e) => clientIds.contains(e.clientId));
    return const Success(null);
  }
}
