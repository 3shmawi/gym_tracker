import 'package:gym_tracker/features/workout/domain/entities/next_workout.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/usecases/suggest_weight.dart';

/// Works out the next workout from the plan and finished sessions.
///
/// The plan advances only when a workout is finished: the day after the
/// last finished one, wrapping around. If the member skipped a day, the
/// same workout waits ([NextWorkout.waitingSince] is set).
///
/// The member can pick the next day themselves (`chosenDay`, e.g. joining
/// mid-plan); that wins until the next finished workout.
/// Out-of-range choices are ignored.
class GetNextWorkout {
  const new({this.suggestWeight = const SuggestWeight()});

  final SuggestWeight suggestWeight;

  NextWorkout call(
    WorkoutPlan plan,
    List<WorkoutSession> history, {
    required DateTime now,
    int? chosenDay,
  }) {
    if (plan.days.isEmpty) {
      throw ArgumentError.value(plan, 'plan', 'has no days');
    }
    final sorted = [...history]
      ..sort((a, b) => a.finishedAt.compareTo(b.finishedAt));
    final last = sorted.isEmpty ? null : sorted.last;
    final chosen =
        chosenDay != null && chosenDay >= 0 && chosenDay < plan.days.length
        ? chosenDay
        : null;
    final dayIndex =
        chosen ?? (last == null ? 0 : (last.dayIndex + 1) % plan.days.length);
    final day = plan.days[dayIndex];

    return NextWorkout(
      dayIndex: dayIndex,
      days: plan.days,
      day: day,
      waitingSince: chosen == null ? _waitingSince(last, now) : null,
      exercises: [
        for (final exercise in day.exercises)
          () {
            final lastSets = _lastSetsFor(exercise.id, sorted);
            return ExercisePreview(
              exercise: exercise,
              lastSets: lastSets,
              suggestion: suggestWeight(exercise, lastSets),
            );
          }(),
      ],
    );
  }

  /// The most recent session that has this exercise (it may be another
  /// day of the plan with the same exercise, e.g. day 1 and day 4).
  List<LoggedSet> _lastSetsFor(String id, List<WorkoutSession> sorted) {
    for (final session in sorted.reversed) {
      final sets = session.setsFor(id);
      if (sets.isNotEmpty) return sets;
    }
    return const [];
  }

  /// The next workout was due the day after the last one. If today is past
  /// that, it has been waiting since then.
  DateTime? _waitingSince(WorkoutSession? last, DateTime now) {
    if (last == null) return null;
    final finished = last.finishedAt.toLocal();
    final due = DateTime(finished.year, finished.month, finished.day + 1);
    final today = DateTime(now.year, now.month, now.day);
    return today.isAfter(due) ? due : null;
  }
}
