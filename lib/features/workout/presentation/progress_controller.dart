import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/domain/entities/exercise_history.dart';
import 'package:gym_tracker/features/workout/domain/usecases/get_exercise_history.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';

const _getHistory = GetExerciseHistory();

/// Every plan exercise with its first and latest weight; null when there is
/// no plan. Errors carry an `AppFailure`, for `ErrorView`. No automatic
/// retry: the repository already retries, and the error has Try again.
final FutureProvider<List<ExerciseProgress>?> progressOverviewProvider =
    FutureProvider.autoDispose<List<ExerciseProgress>?>((ref) async {
      final repo = ref.watch(workoutRepositoryProvider);
      final plan = _unwrap(await repo.loadPlan());
      if (plan == null) return null;
      return _getHistory.overview(plan, _unwrap(await repo.loadHistory()));
    }, retry: (_, _) => null);

/// One exercise's history; null when the id isn't in the plan (e.g. an old
/// or crafted link).
final FutureProviderFamily<ExerciseHistory?, String> exerciseHistoryProvider =
    FutureProvider.autoDispose.family<ExerciseHistory?, String>((
      ref,
      exerciseId,
    ) async {
      final repo = ref.watch(workoutRepositoryProvider);
      final plan = _unwrap(await repo.loadPlan());
      if (plan == null) return null;
      return _getHistory(plan, _unwrap(await repo.loadHistory()), exerciseId);
    }, retry: (_, _) => null);

T _unwrap<T>(Result<T> result) => switch (result) {
  Success(:final value) => value,
  Failed(:final failure) => throw failure,
};
