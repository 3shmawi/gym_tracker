import 'package:gym_tracker/core/media/youtube_link.dart';
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

/// A gym's own how-to video for an exercise (`gym_exercise_videos`,
/// migration 0017): the YouTube id and optional start/end, never a URL.
@immutable
class GymExerciseVideo {
  const new({required this.exerciseId, required this.video});

  final String exerciseId;
  final YouTubeVideoRef video;

  /// A row as stored or read; null for anything outside the rules.
  static GymExerciseVideo? tryParse(Object? json) {
    if (json is! Map) return null;
    final exercise = json['exercise_id'];
    final id = json['video_id'];
    final start = json['start_seconds'];
    final end = json['end_seconds'];
    if (exercise is! String ||
        id is! String ||
        !GymExercisePicture.exerciseIdPattern.hasMatch(exercise) ||
        !YouTubeVideoRef.isValid(id) ||
        (start != null && (start is! int || start < 0 || start > maxSeconds)) ||
        (end != null && (end is! int || end < 1 || end > maxSeconds)) ||
        (start is int && end is int && start >= end)) {
      return null;
    }
    return GymExerciseVideo(
      exerciseId: exercise,
      video: YouTubeVideoRef(id, start: start as int?, end: end as int?),
    );
  }

  /// 12 h, as the link parser and the database.
  static const maxSeconds = 43200;

  Map<String, Object> toJson() => {
    'exercise_id': exerciseId,
    'video_id': video.id,
    'start_seconds': ?video.start,
    'end_seconds': ?video.end,
  };

  @override
  bool operator ==(Object other) =>
      other is GymExerciseVideo &&
      other.exerciseId == exerciseId &&
      other.video.id == video.id &&
      other.video.start == video.start &&
      other.video.end == video.end;

  @override
  int get hashCode => Object.hash(exerciseId, video.id, video.start, video.end);
}

/// What a gym chose to show on its exercise screens. Read through the gym
/// data layer with a copy on the phone (like the gym plan); the gym's video
/// joins it in a later step.
@immutable
class GymMedia {
  /// Keeps the order and the limits of the database: by position, at most 6
  /// per exercise, a picture once per exercise, at most [maxRows] in all.
  factory fromPictures(
    Iterable<GymExercisePicture> pictures, {
    Iterable<GymExerciseVideo> videos = const [],
  }) {
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
    // One video per exercise (the database's key); the first one wins.
    final byVideo = <String, GymExerciseVideo>{};
    for (final v in videos) {
      if (byVideo.length >= maxVideos) break;
      byVideo.putIfAbsent(v.exerciseId, () => v);
    }
    return GymMedia._({
      for (final e in byExercise.entries)
        e.key: List<GymExercisePicture>.unmodifiable(e.value),
    }, Map.unmodifiable(byVideo));
  }

  /// The phone's copy; anything malformed is dropped, a wrong shape is empty.
  factory fromJson(Object? json) {
    if (json is! Map || json['v'] != 1) return empty;
    final list = json['pictures'];
    if (list is! List) return empty;
    // `videos` came with migration 0017; a copy saved before has none.
    final videos = json['videos'];
    return GymMedia.fromPictures(
      list.map(GymExercisePicture.tryParse).nonNulls,
      videos: videos is List
          ? videos.map(GymExerciseVideo.tryParse).nonNulls
          : const [],
    );
  }

  const new _(this._pictures, [this._videos = const {}]);

  static const empty = GymMedia._({});
  static const maxPicturesPerExercise = 6;
  static const maxRows = 1200;

  /// The database's limit per gym (0017).
  static const maxVideos = 300;

  final Map<String, List<GymExercisePicture>> _pictures;
  final Map<String, GymExerciseVideo> _videos;

  /// The gym's own video for the exercise; null when it set none.
  GymExerciseVideo? videoFor(String exerciseId) => _videos[exerciseId];

  Iterable<GymExerciseVideo> get allVideos => _videos.values;

  /// The exercise's pictures, cover first; empty when the gym chose none.
  List<GymExercisePicture> picturesFor(String exerciseId) =>
      _pictures[exerciseId] ?? const [];

  Iterable<GymExercisePicture> get allPictures =>
      _pictures.values.expand((l) => l);

  bool get isEmpty => _pictures.isEmpty && _videos.isEmpty;

  Map<String, Object> toJson() => {
    'v': 1,
    'pictures': [for (final p in allPictures) p.toJson()],
    if (_videos.isNotEmpty) 'videos': [for (final v in allVideos) v.toJson()],
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
    final va = allVideos.toList();
    final vb = other.allVideos.toList();
    if (va.length != vb.length) return false;
    for (var i = 0; i < va.length; i++) {
      if (va[i] != vb[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(allPictures), Object.hashAll(allVideos));
}
