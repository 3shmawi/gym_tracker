import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:meta/meta.dart';

/// One finished workout's sets of one exercise.
@immutable
class HistoryEntry {
  const new({required this.date, required this.sets, this.change});

  final DateTime date;

  /// In the order done; never empty.
  final List<LoggedSet> sets;

  /// Heaviest weight minus the previous entry's heaviest (kg); null for the
  /// first time, 0 when it stayed the same.
  final double? change;

  double get topWeight =>
      sets.map((s) => s.weight).reduce((a, b) => a > b ? a : b);
}

/// How one exercise moved from the first time to the latest.
@immutable
class ExerciseProgress {
  const new({
    required this.exercise,
    this.first,
    this.latest,
    this.best,
    this.workouts = 0,
  });

  final Exercise exercise;

  /// The first and latest time it was done; null when never done.
  final HistoryEntry? first;
  final HistoryEntry? latest;

  /// The heaviest set ever (most reps at that weight).
  final LoggedSet? best;

  /// Finished workouts that included it.
  final int workouts;

  bool get started => first != null;

  /// Latest heaviest weight minus the first one (kg); null when never done.
  double? get gain =>
      first == null ? null : latest!.topWeight - first!.topWeight;
}

/// A plan day an exercise is on: "Day 1 · Chest & Back".
typedef PlanDayRef = ({int number, LocalizedName name});

/// Every time one exercise was done, newest first, and the progress.
@immutable
class ExerciseHistory {
  const new({
    required this.progress,
    required this.entries,
    this.days = const [],
  });

  final ExerciseProgress progress;

  /// The plan days it is on, in plan order (usually one; an exercise can be
  /// on more than one day).
  final List<PlanDayRef> days;

  /// Newest first.
  final List<HistoryEntry> entries;

  Exercise get exercise => progress.exercise;
}
