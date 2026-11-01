import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/domain/entities/exercise_history.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/usecases/get_exercise_history.dart';

/// "Now" for the progress screens: Monday 3 Nov 2026, evening.
final progressNow = DateTime(2026, 11, 3, 20);

/// Four weeks of day 1 (the member's real numbers), the last one today.
final List<WorkoutSession> progressSessions = [
  for (final (i, press, pulldown, row) in [
    (0, 20.0, 45.0, 50.0),
    (1, 20.0, 47.5, 50.0),
    (2, 22.5, 50.0, 47.5),
    (3, 22.5, 52.5, 50.0),
  ])
    WorkoutSession(
      dayIndex: 0,
      finishedAt: DateTime(2026, 10, 13 + i * 7, 19),
      sets: [
        for (final r in [12, 12, 11])
          LoggedSet(exerciseId: 'flat_db_press', weight: press, reps: r),
        for (final r in [12, 12, 12])
          LoggedSet(exerciseId: 'wide_lat_pulldown', weight: pulldown, reps: r),
        for (final r in [10, 9, 8])
          LoggedSet(exerciseId: 'close_grip_row', weight: row, reps: r),
      ],
    ),
];

List<ExerciseProgress> progressOverview([List<WorkoutSession>? sessions]) =>
    const GetExerciseHistory().overview(
      PlanTemplates.fiveDaySplit,
      sessions ?? progressSessions,
    );

ExerciseHistory exerciseHistory(String id) => const GetExerciseHistory()(
  PlanTemplates.fiveDaySplit,
  progressSessions,
  id,
)!;
