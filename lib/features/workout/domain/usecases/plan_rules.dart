import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';

/// What a plan may hold. The editor's steppers use the same limits, and
/// `LocalWorkoutRepository.savePlan` refuses a plan outside them.
abstract final class PlanLimits {
  static const minDays = 1;
  static const maxDays = 14;
  static const maxExercisesPerDay = 30;

  /// Characters per name, in each language.
  static const maxNameLength = 40;

  static const minSets = 1;
  static const maxSets = 10;
  static const minReps = 1;
  static const maxReps = 100;

  /// Rest after a set (or a superset round), seconds.
  static const minRest = 0;
  static const maxRest = 600;
  static const restStep = 15;

  /// Weight step choices offered in the editor, kg.
  static const weightSteps = [0.5, 1.0, 1.25, 2.0, 2.5, 5.0];
  static const maxWeightStep = 50.0;

  /// Targets for a new exercise.
  static const newSets = 3;
  static const newReps = 12;
  static const newRest = 90;
  static const newWeightStep = 2.5;
}

/// Why a typed name can't be saved.
enum NameProblem {
  /// Nothing left after trimming.
  empty,

  /// More than [PlanLimits.maxNameLength] characters.
  tooLong,
}

/// Names as typed by the member, cleaned and checked. Hostile text
/// ("'; DROP TABLE", `<script>`, emoji) is only ever stored as text; what
/// is removed is what breaks a one-line label: control and invisible
/// direction-override characters, and runs of spaces or new lines.
abstract final class PlanNames {
  // Control characters (new lines, tabs, NUL, …) and the bidi
  // embedding/override/isolate marks that can flip how a name reads.
  static final _invisible = RegExp(
    r'[\x00-\x1F\x7F-\x9F\u200E\u200F\u202A-\u202E\u2066-\u2069]',
  );
  static final _spaces = RegExp(r'\s+');

  /// [raw] on one line, trimmed.
  static String clean(String raw) =>
      raw.replaceAll(_invisible, ' ').replaceAll(_spaces, ' ').trim();

  /// Characters as the member sees them (an emoji counts once).
  static int length(String name) => name.runes.length;

  /// The problem with one typed field, or null when it can be saved.
  /// [required] is false for a field the other language can fill.
  static NameProblem? check(String raw, {bool required = true}) {
    final name = clean(raw);
    if (name.isEmpty) return required ? NameProblem.empty : null;
    if (length(name) > PlanLimits.maxNameLength) return NameProblem.tooLong;
    return null;
  }

  /// Both fields as a name, or null when they can't be saved. One empty
  /// language takes the other's text.
  static LocalizedName? from({required String ar, required String en}) {
    final a = clean(ar);
    final e = clean(en);
    if (a.isEmpty && e.isEmpty) return null;
    if (check(a, required: false) != null ||
        check(e, required: false) != null) {
      return null;
    }
    return LocalizedName(ar: a.isEmpty ? e : a, en: e.isEmpty ? a : e);
  }

  static bool isValid(LocalizedName name) =>
      name.ar.isNotEmpty &&
      name.en.isNotEmpty &&
      clean(name.ar) == name.ar &&
      clean(name.en) == name.en &&
      length(name.ar) <= PlanLimits.maxNameLength &&
      length(name.en) <= PlanLimits.maxNameLength;
}

/// Checks a whole plan before it is saved. Returns what is wrong, or null.
String? validatePlan(WorkoutPlan plan) {
  if (plan.days.length < PlanLimits.minDays) return 'the plan has no days';
  if (plan.days.length > PlanLimits.maxDays) return 'too many days';
  final dayIds = <String>{};
  for (final day in plan.days) {
    if (day.id.isEmpty || !dayIds.add(day.id)) return 'bad day id';
    if (!PlanNames.isValid(day.name)) return 'bad day name';
    if (day.exercises.length > PlanLimits.maxExercisesPerDay) {
      return 'too many exercises';
    }
    final exerciseIds = <String>{};
    for (final e in day.exercises) {
      if (e.id.isEmpty || !exerciseIds.add(e.id)) return 'bad exercise id';
      if (!PlanNames.isValid(e.name)) return 'bad exercise name';
      if (e.targetSets < PlanLimits.minSets ||
          e.targetSets > PlanLimits.maxSets) {
        return 'sets out of range';
      }
      if (e.targetReps < PlanLimits.minReps ||
          e.targetReps > PlanLimits.maxReps) {
        return 'reps out of range';
      }
      if (e.restSeconds < PlanLimits.minRest ||
          e.restSeconds > PlanLimits.maxRest) {
        return 'rest out of range';
      }
      if (!e.weightStep.isFinite ||
          e.weightStep <= 0 ||
          e.weightStep > PlanLimits.maxWeightStep) {
        return 'weight step out of range';
      }
    }
  }
  return null;
}

/// A new id that is not in [taken]: [prefix], then the time in base 36
/// ("ex-m3k9w2a1b"). Ids are never reused: history is matched by id, so a
/// new exercise must not inherit a deleted one's history.
String newPlanId(String prefix, Set<String> taken, DateTime now) {
  final base = '$prefix-${now.microsecondsSinceEpoch.toRadixString(36)}';
  var id = base;
  for (var n = 2; taken.contains(id); n++) {
    id = '$base-$n';
  }
  return id;
}
