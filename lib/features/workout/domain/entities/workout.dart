import 'package:flutter/foundation.dart';

/// An exercise as it appears in a plan day: what to do, how many sets and
/// reps, and how long to rest after each set.
@immutable
class PlanExercise {
  const new({
    required this.exerciseId,
    required this.nameEn,
    required this.nameAr,
    required this.position,
    required this.sets,
    required this.targetReps,
    required this.restSeconds,
    required this.weightStepKg,
    this.supersetGroup,
  });

  final String exerciseId;
  final String nameEn;
  final String nameAr;
  final int position;
  final int sets;
  final int targetReps;
  final int restSeconds;
  final double weightStepKg;

  /// Exercises with the same group in one day are done back to back.
  final int? supersetGroup;

  String name(String languageCode) => languageCode == 'ar' ? nameAr : nameEn;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlanExercise &&
          other.exerciseId == exerciseId &&
          other.position == position &&
          other.sets == sets &&
          other.targetReps == targetReps &&
          other.restSeconds == restSeconds &&
          other.weightStepKg == weightStepKg &&
          other.supersetGroup == supersetGroup &&
          other.nameEn == nameEn &&
          other.nameAr == nameAr;

  @override
  int get hashCode => Object.hash(
    exerciseId,
    position,
    sets,
    targetReps,
    restSeconds,
    weightStepKg,
    supersetGroup,
    nameEn,
    nameAr,
  );
}

/// One day of the plan. The plan moves day by day only when a session is
/// completed, so a missed calendar day never skips a workout.
@immutable
class PlanDay {
  const new({
    required this.id,
    required this.planId,
    required this.dayOrder,
    required this.nameEn,
    required this.nameAr,
    required this.exercises,
  });

  final String id;
  final String planId;
  final int dayOrder;
  final String nameEn;
  final String nameAr;

  /// Sorted by position.
  final List<PlanExercise> exercises;

  String name(String languageCode) => languageCode == 'ar' ? nameAr : nameEn;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlanDay &&
          other.id == id &&
          other.dayOrder == dayOrder &&
          listEquals(other.exercises, exercises);

  @override
  int get hashCode => Object.hash(id, dayOrder, Object.hashAll(exercises));
}

/// The member's active plan with all its days and where they are in it.
@immutable
class AssignedPlan {
  const new({
    required this.planId,
    required this.name,
    required this.days,
    required this.nextDayOrder,
  });

  final String planId;
  final String name;

  /// Sorted by day order (1..n).
  final List<PlanDay> days;
  final int nextDayOrder;

  PlanDay? get nextDay {
    for (final day in days) {
      if (day.dayOrder == nextDayOrder) return day;
    }
    return days.isEmpty ? null : days.first;
  }

  /// The day after [dayOrder], wrapping to day 1 after the last day — the
  /// same rule as `complete_session()` on the server.
  int dayAfter(int dayOrder) => days.isEmpty ? 1 : (dayOrder % days.length) + 1;

  AssignedPlan copyWith({int? nextDayOrder}) => AssignedPlan(
    planId: planId,
    name: name,
    days: days,
    nextDayOrder: nextDayOrder ?? this.nextDayOrder,
  );
}

enum SessionStatus { inProgress, completed }

@immutable
class WorkoutSession {
  const new({
    required this.id,
    required this.planDayId,
    required this.startedAt,
    this.status = SessionStatus.inProgress,
    this.endedAt,
  });

  final String id;
  final String? planDayId;
  final DateTime startedAt;
  final SessionStatus status;
  final DateTime? endedAt;
}

/// One logged set.
@immutable
class LoggedSet {
  const new({
    required this.id,
    required this.sessionId,
    required this.exerciseId,
    required this.setNumber,
    required this.weightKg,
    required this.reps,
    required this.loggedAt,
  });

  final String id;
  final String sessionId;
  final String exerciseId;
  final int setNumber;
  final double weightKg;
  final int reps;
  final DateTime loggedAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoggedSet &&
          other.id == id &&
          other.sessionId == sessionId &&
          other.exerciseId == exerciseId &&
          other.setNumber == setNumber &&
          other.weightKg == weightKg &&
          other.reps == reps &&
          other.loggedAt == loggedAt;

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    exerciseId,
    setNumber,
    weightKg,
    reps,
    loggedAt,
  );
}
