import 'dart:convert';

import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:meta/meta.dart';

/// What the person chose to do with the workouts already on the phone
/// (docs/decisions/gym_accounts.md §10).
enum SoloImportChoice {
  /// Not asked yet.
  undecided,

  /// "Keep my solo data": nothing leaves the phone. Never asked again.
  keep,

  /// "Skip": not now. Asked again at the next join; always in Profile.
  skip,

  /// "Add my solo history to my account": copying, possibly interrupted.
  copying,

  /// Copied and confirmed by the server; the phone still keeps its copy.
  done,
}

/// One finished workout as `import_solo_data` takes it:
/// `{client_id, day_id, finished_at, sets}`.
@immutable
class ImportSession {
  const new({
    required this.clientId,
    required this.dayId,
    required this.finishedAt,
    required this.sets,
  });

  /// `client_id` = sha256 of `day_id|finished_at|sets` (hex, 64 characters):
  /// a workout has no id of its own, so the same workout always gets the same
  /// id and sending it twice is a no-op (decision doc §17).
  /// `finished_at` is UTC ISO-8601; `sets` is the JSON of the list
  /// (`exercise`, `weight`, `reps`, in this order).
  factory fromSession(WorkoutSession session) {
    final finished = session.finishedAt.toUtc().toIso8601String();
    final sets = [for (final s in session.sets) s.toJson()];
    return ImportSession(
      clientId: session.clientId,
      dayId: session.dayId,
      finishedAt: finished,
      sets: sets,
    );
  }

  final String clientId;
  final String dayId;
  final String finishedAt;
  final List<Map<String, Object?>> sets;

  Map<String, Object?> toJson() => {
    'client_id': clientId,
    'day_id': dayId,
    'finished_at': finishedAt,
    'sets': sets,
  };

  static final _id = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  /// The server's own rules (migration 0009), checked first so one workout it
  /// would refuse cannot block the other 49 of its chunk. Null when fine.
  static String? problemWith(WorkoutSession s, {required DateTime now}) {
    if (!_id.hasMatch(s.dayId)) return 'bad day id';
    final at = s.finishedAt.toUtc();
    if (at.isBefore(DateTime.utc(2020)) ||
        at.isAfter(now.toUtc().add(const Duration(days: 1)))) {
      return 'finish time out of range';
    }
    if (s.sets.length > 500) return 'too many sets';
    for (final set in s.sets) {
      if (!_id.hasMatch(set.exerciseId)) return 'bad exercise id';
      if (!(set.weight >= 0 && set.weight <= 1000)) return 'weight';
      if (set.reps < 0 || set.reps > 1000) return 'reps';
    }
    if (utf8.encode(jsonEncode([for (final x in s.sets) x.toJson()])).length >
        65536) {
      return 'sets too large';
    }
    return null;
  }
}

/// The server's answer to one chunk.
@immutable
class ImportAck {
  const new({
    required this.imported,
    required this.skipped,
    required this.planSaved,
    required this.soloTotal,
  });

  factory fromJson(Object? json) {
    if (json is! Map) throw const FormatException('import answer');
    int count(String key) {
      final v = json[key];
      if (v is! int || v < 0) throw FormatException('import answer: $key');
      return v;
    }

    return ImportAck(
      imported: count('imported'),
      skipped: count('skipped'),
      planSaved: json['plan_saved'] == true,
      soloTotal: count('solo_total'),
    );
  }

  final int imported;
  final int skipped;
  final bool planSaved;

  /// All the person's solo workouts on the server after this chunk.
  final int soloTotal;
}

/// Where an import stands, kept on the phone so it can resume.
@immutable
class SoloImportStatus {
  const new({
    this.choice = SoloImportChoice.undecided,
    this.nextIndex = 0,
    this.migratedAt,
  });

  final SoloImportChoice choice;

  /// How many of the (sorted, deduplicated) workouts the server acknowledged
  /// in this run. Progress only: a run always starts from 0 (idempotent).
  final int nextIndex;
  final DateTime? migratedAt;

  SoloImportStatus copyWith({
    SoloImportChoice? choice,
    int? nextIndex,
    DateTime? migratedAt,
  }) => SoloImportStatus(
    choice: choice ?? this.choice,
    nextIndex: nextIndex ?? this.nextIndex,
    migratedAt: migratedAt ?? this.migratedAt,
  );

  @override
  bool operator ==(Object other) =>
      other is SoloImportStatus &&
      other.choice == choice &&
      other.nextIndex == nextIndex &&
      other.migratedAt == migratedAt;

  @override
  int get hashCode => Object.hash(choice, nextIndex, migratedAt);
}
