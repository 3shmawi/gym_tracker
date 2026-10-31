import 'package:gym_tracker/features/workout/domain/entities/workout.dart';

/// JSON mapping for the plan (Supabase rows ↔ entities ↔ device cache).
/// The cache uses the same shape as the Supabase nested select, so one
/// parser serves both.
abstract final class WorkoutJson {
  /// Supabase: `plan_assignments` row with nested `plans → plan_days →
  /// plan_exercises → exercises` (see SupabaseWorkoutRemote.planSelect).
  static AssignedPlan planFromAssignment(Map<String, dynamic> json) {
    final plan = json['plans'] as Map<String, dynamic>;
    final days =
        (plan['plan_days'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map((d) => _day(d, plan['id'] as String))
            .toList()
          ..sort((a, b) => a.dayOrder.compareTo(b.dayOrder));
    return AssignedPlan(
      planId: plan['id'] as String,
      name: plan['name'] as String,
      days: days,
      nextDayOrder: json['next_day_order'] as int,
    );
  }

  static PlanDay _day(Map<String, dynamic> json, String planId) {
    final exercises =
        (json['plan_exercises'] as List<dynamic>)
            .cast<Map<String, dynamic>>()
            .map(_exercise)
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    return PlanDay(
      id: json['id'] as String,
      planId: planId,
      dayOrder: json['day_order'] as int,
      nameEn: json['name_en'] as String,
      nameAr: json['name_ar'] as String,
      exercises: exercises,
    );
  }

  static PlanExercise _exercise(Map<String, dynamic> json) {
    final exercise = json['exercises'] as Map<String, dynamic>;
    return PlanExercise(
      exerciseId: exercise['id'] as String,
      nameEn: exercise['name_en'] as String,
      nameAr: exercise['name_ar'] as String,
      position: json['position'] as int,
      sets: json['sets'] as int,
      targetReps: json['target_reps'] as int,
      restSeconds: json['rest_seconds'] as int,
      weightStepKg: (json['weight_step_kg'] as num).toDouble(),
      supersetGroup: json['superset_group'] as int?,
    );
  }

  static Map<String, dynamic> planToAssignment(AssignedPlan plan) => {
    'next_day_order': plan.nextDayOrder,
    'plans': {
      'id': plan.planId,
      'name': plan.name,
      'plan_days': [
        for (final day in plan.days)
          {
            'id': day.id,
            'day_order': day.dayOrder,
            'name_en': day.nameEn,
            'name_ar': day.nameAr,
            'plan_exercises': [
              for (final e in day.exercises)
                {
                  'position': e.position,
                  'sets': e.sets,
                  'target_reps': e.targetReps,
                  'rest_seconds': e.restSeconds,
                  'weight_step_kg': e.weightStepKg,
                  'superset_group': e.supersetGroup,
                  'exercises': {
                    'id': e.exerciseId,
                    'name_en': e.nameEn,
                    'name_ar': e.nameAr,
                  },
                },
            ],
          },
      ],
    },
  };

  static LoggedSet setFromRow(Map<String, dynamic> json) => LoggedSet(
    id: json['id'] as String,
    sessionId: json['session_id'] as String,
    exerciseId: json['exercise_id'] as String,
    setNumber: json['set_number'] as int,
    weightKg: (json['weight_kg'] as num).toDouble(),
    reps: json['reps'] as int,
    loggedAt: DateTime.parse(json['logged_at'] as String),
  );

  static Map<String, dynamic> setToRow(LoggedSet set) => {
    'id': set.id,
    'session_id': set.sessionId,
    'exercise_id': set.exerciseId,
    'set_number': set.setNumber,
    'weight_kg': set.weightKg,
    'reps': set.reps,
    'logged_at': set.loggedAt.toUtc().toIso8601String(),
  };

  static Map<String, dynamic> sessionToRow(WorkoutSession session) => {
    'id': session.id,
    'plan_day_id': session.planDayId,
    'started_at': session.startedAt.toUtc().toIso8601String(),
  };
}
