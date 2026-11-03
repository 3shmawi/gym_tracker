import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/usecases/get_next_workout.dart';
import 'package:gym_tracker/features/workout/domain/usecases/plan_rules.dart';

/// Why an edit was refused.
enum PlanEditError {
  /// The day of the workout in progress: finish or discard it first.
  lockedDay,

  /// A plan keeps at least one day.
  lastDay,

  /// The day or exercise isn't in the plan (an old link, a stale screen).
  notFound,

  /// A name that can't be saved (empty or too long).
  invalidName,

  /// [PlanLimits.maxDays] or [PlanLimits.maxExercisesPerDay] reached.
  tooMany,

  /// The member's gym doesn't let them make this change (or took the right
  /// away while the editor was open).
  notAllowed,

  /// The day already has this exercise (the same id twice in one day is
  /// not allowed).
  duplicate,
}

class PlanEditException implements Exception {
  const new(this.reason);
  final PlanEditError reason;

  @override
  String toString() => 'PlanEditException(${reason.name})';
}

/// Every change the plan editor makes, as pure functions: plan in, new plan
/// out, or a [PlanEditException]. `lockedDayId` is the day of the workout in
/// progress; its name and exercises can't change and it can't be deleted
/// (it can still move: the workout points at it by id).
///
/// Days and exercises are found by id. Targets are clamped to
/// [PlanLimits]. The last exercise of a day never stays "superset with
/// next" (there is no next).
class EditPlan {
  const new();

  WorkoutPlan addDay(
    WorkoutPlan plan,
    LocalizedName name, {
    required String id,
  }) {
    if (plan.days.length >= PlanLimits.maxDays) {
      throw const PlanEditException(PlanEditError.tooMany);
    }
    _checkName(name);
    return WorkoutPlan(
      days: [
        ...plan.days,
        WorkoutDay(id: id, name: name, exercises: const []),
      ],
    );
  }

  WorkoutPlan renameDay(
    WorkoutPlan plan,
    String dayId,
    LocalizedName name, {
    String? lockedDayId,
  }) {
    _checkName(name);
    return _updateDay(
      plan,
      dayId,
      lockedDayId,
      (day) => day.copyWith(name: name),
    );
  }

  WorkoutPlan deleteDay(WorkoutPlan plan, String dayId, {String? lockedDayId}) {
    _dayIndex(plan, dayId, lockedDayId);
    if (plan.days.length <= PlanLimits.minDays) {
      throw const PlanEditException(PlanEditError.lastDay);
    }
    return WorkoutPlan(days: [...plan.days.where((d) => d.id != dayId)]);
  }

  /// Moves the day at [from] so it ends up at [to] (both 0-based, [to] in
  /// the list after the move).
  WorkoutPlan moveDay(WorkoutPlan plan, int from, int to) =>
      WorkoutPlan(days: _move(plan.days, from, to));

  WorkoutPlan addExercise(
    WorkoutPlan plan,
    String dayId,
    LocalizedName name, {
    required String id,
    String? lockedDayId,
  }) {
    _checkName(name);
    return _updateDay(plan, dayId, lockedDayId, (day) {
      if (day.exercises.length >= PlanLimits.maxExercisesPerDay) {
        throw const PlanEditException(PlanEditError.tooMany);
      }
      return day.copyWith(
        exercises: [
          ...day.exercises,
          // Defaults: PlanLimits.newSets × newReps, newRest, newWeightStep.
          Exercise(id: id, name: name),
        ],
      );
    });
  }

  /// Adds [exercise] as it is (its id, name and targets) to the day. Used by
  /// the library: the id is the library's, so the member's earlier workouts
  /// of it show up again. The same id may be in different days, not twice in
  /// one.
  WorkoutPlan addLibraryExercise(
    WorkoutPlan plan,
    String dayId,
    Exercise exercise, {
    String? lockedDayId,
  }) => _updateDay(plan, dayId, lockedDayId, (day) {
    if (day.exercises.any((e) => e.id == exercise.id)) {
      throw const PlanEditException(PlanEditError.duplicate);
    }
    if (day.exercises.length >= PlanLimits.maxExercisesPerDay) {
      throw const PlanEditException(PlanEditError.tooMany);
    }
    return day.copyWith(exercises: [...day.exercises, exercise]);
  });

  WorkoutPlan renameExercise(
    WorkoutPlan plan,
    String dayId,
    String exerciseId,
    LocalizedName name, {
    String? lockedDayId,
  }) {
    _checkName(name);
    return _updateExercise(
      plan,
      dayId,
      exerciseId,
      lockedDayId,
      (e) => e.copyWith(name: name),
    );
  }

  WorkoutPlan deleteExercise(
    WorkoutPlan plan,
    String dayId,
    String exerciseId, {
    String? lockedDayId,
  }) => _updateDay(plan, dayId, lockedDayId, (day) {
    if (!day.exercises.any((e) => e.id == exerciseId)) {
      throw const PlanEditException(PlanEditError.notFound);
    }
    return day.copyWith(
      exercises: [...day.exercises.where((e) => e.id != exerciseId)],
    );
  });

  WorkoutPlan moveExercise(
    WorkoutPlan plan,
    String dayId,
    int from,
    int to, {
    String? lockedDayId,
  }) => _updateDay(
    plan,
    dayId,
    lockedDayId,
    (day) => day.copyWith(exercises: _move(day.exercises, from, to)),
  );

  WorkoutPlan setSuperset(
    WorkoutPlan plan,
    String dayId,
    String exerciseId, {
    required bool withNext,
    String? lockedDayId,
  }) => _updateExercise(
    plan,
    dayId,
    exerciseId,
    lockedDayId,
    (e) => e.copyWith(supersetWithNext: withNext),
  );

  /// Changes the targets given; each is clamped to [PlanLimits]. A weight
  /// step that isn't a finite number above 0 is refused.
  WorkoutPlan setTargets(
    WorkoutPlan plan,
    String dayId,
    String exerciseId, {
    int? sets,
    int? reps,
    int? restSeconds,
    double? weightStep,
    String? lockedDayId,
  }) {
    if (weightStep != null &&
        (!weightStep.isFinite ||
            weightStep <= 0 ||
            weightStep > PlanLimits.maxWeightStep)) {
      throw const PlanEditException(PlanEditError.notFound);
    }
    return _updateExercise(
      plan,
      dayId,
      exerciseId,
      lockedDayId,
      (e) => e.copyWith(
        targetSets: sets?.clamp(PlanLimits.minSets, PlanLimits.maxSets),
        targetReps: reps?.clamp(PlanLimits.minReps, PlanLimits.maxReps),
        restSeconds: restSeconds?.clamp(PlanLimits.minRest, PlanLimits.maxRest),
        weightStep: weightStep,
      ),
    );
  }

  static void _checkName(LocalizedName name) {
    if (!PlanNames.isValid(name)) {
      throw const PlanEditException(PlanEditError.invalidName);
    }
  }

  static int _dayIndex(WorkoutPlan plan, String dayId, String? lockedDayId) {
    final i = plan.indexOfDay(dayId);
    if (i < 0) throw const PlanEditException(PlanEditError.notFound);
    if (dayId == lockedDayId) {
      throw const PlanEditException(PlanEditError.lockedDay);
    }
    return i;
  }

  static WorkoutPlan _updateDay(
    WorkoutPlan plan,
    String dayId,
    String? lockedDayId,
    WorkoutDay Function(WorkoutDay day) change,
  ) {
    final i = _dayIndex(plan, dayId, lockedDayId);
    final days = [...plan.days];
    days[i] = _endSupersets(change(days[i]));
    return WorkoutPlan(days: days);
  }

  static WorkoutPlan _updateExercise(
    WorkoutPlan plan,
    String dayId,
    String exerciseId,
    String? lockedDayId,
    Exercise Function(Exercise exercise) change,
  ) => _updateDay(plan, dayId, lockedDayId, (day) {
    final i = day.exercises.indexWhere((e) => e.id == exerciseId);
    if (i < 0) throw const PlanEditException(PlanEditError.notFound);
    final exercises = [...day.exercises];
    exercises[i] = change(exercises[i]);
    return day.copyWith(exercises: exercises);
  });

  /// The last exercise has no "next" to superset with.
  static WorkoutDay _endSupersets(WorkoutDay day) {
    final last = day.exercises.lastOrNull;
    if (last == null || !last.supersetWithNext) return day;
    return day.copyWith(
      exercises: [
        ...day.exercises.take(day.exercises.length - 1),
        last.copyWith(supersetWithNext: false),
      ],
    );
  }

  static List<T> _move<T>(List<T> items, int from, int to) {
    if (from < 0 || from >= items.length || to < 0 || to >= items.length) {
      throw const PlanEditException(PlanEditError.notFound);
    }
    final list = [...items];
    final item = list.removeAt(from);
    list.insert(to, item);
    return list;
  }
}

/// After a plan edit, the workout that was waiting stays waiting: adding,
/// renaming, reordering or deleting other days never changes "next". If
/// the waiting day itself was deleted, the next day after it (in the old
/// order) that still exists waits instead.
///
/// Returns the [ChosenDay] to save with the edited plan: the member's own
/// choice when it still holds, a pin (`byEdit`) when the history alone
/// would now point elsewhere, or null when it already points there.
class KeepNextWorkout {
  const new({this.getNext = const GetNextWorkout()});

  final GetNextWorkout getNext;

  ChosenDay? call({
    required WorkoutPlan? before,
    required WorkoutPlan after,
    required List<WorkoutSession> history,
    required ChosenDay? chosen,
    required DateTime now,
  }) {
    if (after.days.isEmpty) return null;
    if (before == null || before.days.isEmpty) return null;
    final waiting = getNext(before, history, now: now, chosenDay: chosen).day;
    final target = _survivor(before, after, waiting.id);
    if (chosen != null && !chosen.byEdit && chosen.dayId == target) {
      return chosen;
    }
    final natural = getNext(after, history, now: now).day.id;
    return natural == target ? null : ChosenDay(target, byEdit: true);
  }

  /// [dayId] if [after] still has it, else the next day after it in
  /// [before] that [after] has, else [after]'s first day.
  static String _survivor(WorkoutPlan before, WorkoutPlan after, String dayId) {
    final start = before.indexOfDay(dayId);
    for (var k = 0; k < before.days.length; k++) {
      final id = before.days[(start + k) % before.days.length].id;
      if (after.indexOfDay(id) >= 0) return id;
    }
    return after.days.first.id;
  }
}

/// Every id the plan and history use, so a new id never repeats one.
Set<String> takenIds(WorkoutPlan plan, List<WorkoutSession> history) => {
  for (final d in plan.days) ...[d.id, for (final e in d.exercises) e.id],
  for (final s in history) ...[
    s.dayId,
    for (final set in s.sets) set.exerciseId,
  ],
};
