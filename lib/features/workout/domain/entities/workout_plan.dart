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

  @override
  String toString() => 'LocalizedName($ar, $en)';
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

  /// Stable id, used to find this exercise's history. Never reused for
  /// another exercise.
  final String id;
  final LocalizedName name;
  final int targetSets;
  final int targetReps;
  final int restSeconds;

  /// Smallest weight change on this machine, in kg.
  final double weightStep;

  /// Done back to back with the next exercise; rest after the pair.
  final bool supersetWithNext;

  Exercise copyWith({
    LocalizedName? name,
    int? targetSets,
    int? targetReps,
    int? restSeconds,
    double? weightStep,
    bool? supersetWithNext,
  }) => Exercise(
    id: id,
    name: name ?? this.name,
    targetSets: targetSets ?? this.targetSets,
    targetReps: targetReps ?? this.targetReps,
    restSeconds: restSeconds ?? this.restSeconds,
    weightStep: weightStep ?? this.weightStep,
    supersetWithNext: supersetWithNext ?? this.supersetWithNext,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name.toJson(),
    'sets': targetSets,
    'reps': targetReps,
    'rest': restSeconds,
    'step': weightStep,
    'superset': supersetWithNext,
  };

  @override
  bool operator ==(Object other) =>
      other is Exercise &&
      other.id == id &&
      other.name == name &&
      other.targetSets == targetSets &&
      other.targetReps == targetReps &&
      other.restSeconds == restSeconds &&
      other.weightStep == weightStep &&
      other.supersetWithNext == supersetWithNext;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    targetSets,
    targetReps,
    restSeconds,
    weightStep,
    supersetWithNext,
  );
}

/// The id a day gets when it was saved before days had ids: its 1-based
/// position then (`day-1` …). Sessions, drafts and the chosen day saved
/// back then stored the position, so they map to the same id.
String legacyDayId(int index) => 'day-${index + 1}';

/// One day of the plan (e.g. "بنش وضهر").
@immutable
class WorkoutDay {
  const new({required this.id, required this.name, required this.exercises});

  /// [fallbackId] is used for days stored before they had ids.
  factory fromJson(Map<String, Object?> json, {required String fallbackId}) =>
      WorkoutDay(
        id: json['id'] as String? ?? fallbackId,
        name: LocalizedName.fromJson(json['name']! as Map<String, Object?>),
        exercises: [
          for (final e in json['exercises']! as List<Object?>)
            Exercise.fromJson(e! as Map<String, Object?>),
        ],
      );

  /// Stable id: finished workouts, the workout in progress and the chosen
  /// day point at it, so days can be reordered or deleted safely.
  final String id;
  final LocalizedName name;
  final List<Exercise> exercises;

  int get totalSets => exercises.fold(0, (sum, e) => sum + e.targetSets);

  WorkoutDay copyWith({LocalizedName? name, List<Exercise>? exercises}) =>
      WorkoutDay(
        id: id,
        name: name ?? this.name,
        exercises: exercises ?? this.exercises,
      );

  Map<String, Object?> toJson() => {
    'id': id,
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
      for (final (i, d) in (json['days']! as List<Object?>).indexed)
        WorkoutDay.fromJson(
          d! as Map<String, Object?>,
          fallbackId: legacyDayId(i),
        ),
    ],
  );

  final List<WorkoutDay> days;

  /// The position of the day with [id], or -1.
  int indexOfDay(String? id) => days.indexWhere((d) => d.id == id);

  WorkoutDay? dayById(String? id) {
    final i = indexOfDay(id);
    return i < 0 ? null : days[i];
  }

  Map<String, Object?> toJson() => {
    'days': [for (final d in days) d.toJson()],
  };
}
