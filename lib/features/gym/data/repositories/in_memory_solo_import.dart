import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/solo_import.dart';
import 'package:gym_tracker/features/gym/domain/repositories/solo_import_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';

/// Memory only: the default until `Dependencies.init`, and a fake for tests.
class InMemorySoloImportStore implements SoloImportStore {
  new([this.status = const SoloImportStatus()]);

  SoloImportStatus status;

  @override
  Future<Result<SoloImportStatus>> load() async => Success(status);

  @override
  Future<Result<void>> save(SoloImportStatus next) async {
    status = next;
    return const Success(null);
  }

  @override
  Future<Result<void>> clear() async {
    status = const SoloImportStatus();
    return const Success(null);
  }
}

/// Used without Supabase: copying cannot work and says "offline".
class UnconfiguredSoloImportRepository implements SoloImportRepository {
  const new();

  @override
  Future<Result<ImportAck>> importChunk(
    List<ImportSession> sessions, {
    WorkoutPlan? plan,
  }) async => const Failed(NetworkFailure());
}
