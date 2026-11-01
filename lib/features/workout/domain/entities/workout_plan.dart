import 'package:meta/meta.dart';

/// A name in both languages: exercises and days are known by either
/// ("فراشة" / "Pec Deck").
@immutable
class LocalizedName {
  const new({required this.ar, required this.en});
  factory fromJson(Map<String, Object?> json) =>
      LocalizedName(ar: json['ar']! as String, en: json['en']! as String);

  final String ar;
  final String en;

  /// The name in [languageCode], the other language as fallback.
  String of(String languageCode) => languageCode == 'ar' ? ar : en;

  /// The other language, shown small under the main name.
  String other(String languageCode) => languageCode == 'ar' ? en : ar;

  Map<String, Object?> toJson() => {'ar': ar, 'en': en};

  @override
  bool operator ==(Object other) =>
      other is LocalizedName && other.ar == ar && other.en == en;

  @override
  int get hashCode => Object.hash(ar, en);
}

/// One exercise in a plan day, with its targets.
@immutable
class Exercise {
  const new({
    required this.id,
    required this.name,
    this.targetSets = 3,
    this.targetReps = 12,
    this.restSeconds = 90,
    this.weightStep = 2.5,
    this.supersetWithNext = false,
  });
  factory fromJson(Map<String, Object?> json) => Exercise(
    id: json['id']! as String,
    name: LocalizedName.fromJson(json['name']! as Map<String, Object?>),
    targetSets: json['sets']! as int,
    targetReps: json['reps']! as int,
    restSeconds: json['rest']! as int,
    weightStep: (json['step']! as num).toDouble(),
    supersetWithNext: json['superset']! as bool,
  );

  /// Stable id, used to find this exercise's history.
  final String id;
  final LocalizedName name;
  final int targetSets;
  final int targetReps;
  final int restSeconds;

  /// Smallest weight change on this machine, in kg.
  final double weightStep;

  /// Done back to back with the next exercise; rest after the pair.
  final bool supersetWithNext;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name.toJson(),
    'sets': targetSets,
    'reps': targetReps,
    'rest': restSeconds,
    'step': weightStep,
    'superset': supersetWithNext,
  };
}

/// One day of the plan (e.g. "بنش وضهر").
@immutable
class WorkoutDay {
  const new({required this.name, required this.exercises});
  factory fromJson(Map<String, Object?> json) => WorkoutDay(
    name: LocalizedName.fromJson(json['name']! as Map<String, Object?>),
    exercises: [
      for (final e in json['exercises']! as List<Object?>)
        Exercise.fromJson(e! as Map<String, Object?>),
    ],
  );

  final LocalizedName name;
  final List<Exercise> exercises;

  int get totalSets => exercises.fold(0, (sum, e) => sum + e.targetSets);

  Map<String, Object?> toJson() => {
    'name': name.toJson(),
    'exercises': [for (final e in exercises) e.toJson()],
  };
}

/// The member's plan: N days done in order. It advances by finished
/// session, not by calendar day.
@immutable
class WorkoutPlan {
  const new({required this.days});
  factory fromJson(Map<String, Object?> json) => WorkoutPlan(
    days: [
      for (final d in json['days']! as List<Object?>)
        WorkoutDay.fromJson(d! as Map<String, Object?>),
    ],
  );

  final List<WorkoutDay> days;

  Map<String, Object?> toJson() => {
    'days': [for (final d in days) d.toJson()],
  };
}
