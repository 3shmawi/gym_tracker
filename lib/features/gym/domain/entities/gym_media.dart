import 'package:meta/meta.dart';

/// One picture a gym's captain chose for an exercise (`gym_exercise_images`,
/// migration 0015). Only the library's `public_id` is kept: the URL is built
/// on the phone by a fixed builder.
@immutable
class GymExercisePicture {
  const new({
    required this.exerciseId,
    required this.publicId,
    required this.position,
  });

  /// A library id (`flat_db_press`) or a plan editor id (`ex-m3k9w2a1b`).
  static final exerciseIdPattern = RegExp(
    r'^(?:[a-z][a-z0-9_]{0,63}|ex-[a-z0-9]{1,20}(?:-[0-9]{1,4})?)$',
  );

  /// `exercises/ek-<id>-<frame>` (the library's public ids).
  static final publicIdPattern = RegExp(r'^exercises/[a-z0-9][a-z0-9-]{0,79}$');

  final String exerciseId;
  final String publicId;
  final int position;

  /// The library exercise the picture shows (`ek-0055`), and which frame
  /// (`tension` = start of the move, `relaxation` = end); null for an id
  /// outside the `ek-<id>-<frame>` naming.
  String? get exerciseKey => _parts?.$1;
  String? get frame => _parts?.$2;

  (String, String)? get _parts {
    final m = RegExp(r'^exercises/(ek-[a-z0-9]+)-(tension|relaxation)$')
        .firstMatch(publicId);
    return m == null ? null : (m.group(1)!, m.group(2)!);
  }

  /// A row as stored or read; null for any row outside the rules (the
  /// database enforces them too; a bad row is dropped, never shown).
  static GymExercisePicture? tryParse(Object? json) {
    if (json is! Map) return null;
    final exercise = json['exercise_id'];
    final publicId = json['public_id'];
    final position = json['position'];
    if (exercise is! String ||
        publicId is! String ||
        position is! int ||
        !exerciseIdPattern.hasMatch(exercise) ||
        !publicIdPattern.hasMatch(publicId) ||
        position < 1 ||
        position > GymMedia.maxPicturesPerExercise) {
      return null;
    }
    return GymExercisePicture(
      exerciseId: exercise,
      publicId: publicId,
      position: position,
    );
  }

  Map<String, Object> toJson() => {
    'exercise_id': exerciseId,
    'public_id': publicId,
    'position': position,
  };

  @override
  bool operator ==(Object other) =>
      other is GymExercisePicture &&
      other.exerciseId == exerciseId &&
      other.publicId == publicId &&
      other.position == position;

  @override
  int get hashCode => Object.hash(exerciseId, publicId, position);
}

/// What a gym chose to show on its exercise screens. Read through the gym
/// data layer with a copy on the phone (like the gym plan); the gym's video
/// joins it in a later step.
@immutable
class GymMedia {
  /// Keeps the order and the limits of the database: by position, at most 6
  /// per exercise, a picture once per exercise, at most [maxRows] in all.
  factory fromPictures(Iterable<GymExercisePicture> pictures) {
    final byExercise = <String, List<GymExercisePicture>>{};
    var total = 0;
    final sorted = [...pictures]
      ..sort((a, b) {
        final e = a.exerciseId.compareTo(b.exerciseId);
        return e != 0 ? e : a.position.compareTo(b.position);
      });
    for (final p in sorted) {
      if (total >= maxRows) break;
      final list = byExercise.putIfAbsent(p.exerciseId, () => []);
      final clash = list.any(
        (o) => o.publicId == p.publicId || o.position == p.position,
      );
      if (list.length >= maxPicturesPerExercise || clash) {
        continue;
      }
      list.add(p);
      total++;
    }
    return GymMedia._({
      for (final e in byExercise.entries)
        e.key: List<GymExercisePicture>.unmodifiable(e.value),
    });
  }

  /// The phone's copy; anything malformed is dropped, a wrong shape is empty.
  factory fromJson(Object? json) {
    if (json is! Map || json['v'] != 1) return empty;
    final list = json['pictures'];
    if (list is! List) return empty;
    return GymMedia.fromPictures(
      list.map(GymExercisePicture.tryParse).nonNulls,
    );
  }

  const new _(this._pictures);

  static const empty = GymMedia._({});
  static const maxPicturesPerExercise = 6;
  static const maxRows = 1200;

  final Map<String, List<GymExercisePicture>> _pictures;

  /// The exercise's pictures, cover first; empty when the gym chose none.
  List<GymExercisePicture> picturesFor(String exerciseId) =>
      _pictures[exerciseId] ?? const [];

  Iterable<GymExercisePicture> get allPictures =>
      _pictures.values.expand((l) => l);

  bool get isEmpty => _pictures.isEmpty;

  Map<String, Object> toJson() => {
    'v': 1,
    'pictures': [for (final p in allPictures) p.toJson()],
  };

  @override
  bool operator ==(Object other) {
    if (other is! GymMedia) return false;
    final a = allPictures.toList();
    final b = other.allPictures.toList();
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(allPictures);
}
