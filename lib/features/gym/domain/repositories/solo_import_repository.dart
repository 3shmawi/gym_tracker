import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/solo_import.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';

/// The server half of "Add my solo history to my account".
abstract interface class SoloImportRepository {
  /// Sends up to [maxChunk] workouts (and, with the first chunk, the plan).
  /// All-or-nothing on the server; workouts already there are skipped.
  Future<Result<ImportAck>> importChunk(
    List<ImportSession> sessions, {
    WorkoutPlan? plan,
  });
}

const maxChunk = 50;

/// Where the answer to "what about my solo data?" and the copy's progress live
/// (on the phone).
abstract interface class SoloImportStore {
  Future<Result<SoloImportStatus>> load();
  Future<Result<void>> save(SoloImportStatus status);
  Future<Result<void>> clear();
}
