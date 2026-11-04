import 'package:gym_tracker/features/gym/domain/entities/gym_media.dart';
import 'package:meta/meta.dart';

/// A picture of the shared library (`exercise_images`, migration 0013), as
/// the picker shows it. Only ids and the English title: the URL is built on
/// the phone by the fixed builder.
@immutable
class CatalogPicture {
  const new({
    required this.publicId,
    required this.exerciseKey,
    required this.frame,
    required this.title,
  });

  /// `exercises/ek-0055-tension`.
  final String publicId;

  /// `ek-0055`: the two frames of one move share it.
  final String exerciseKey;

  /// `tension` (start of the move) or `relaxation` (end).
  final String frame;
  final String title;

  static final _key = RegExp(r'^ek-[a-z0-9]{1,20}$');

  /// Control characters and bidi overrides / isolates.
  static final _unsafe = RegExp(
    '[\u0000-\u001F\u007F-\u009F\u202A-\u202E\u2066-\u2069]',
  );

  /// A row as read; null for anything outside the rules (dropped, never
  /// shown).
  static CatalogPicture? tryParse(Object? json) {
    if (json is! Map) return null;
    final id = json['public_id'];
    final key = json['exercise_key'];
    final frame = json['frame'];
    final title = json['title_en'];
    if (id is! String ||
        key is! String ||
        frame is! String ||
        !GymExercisePicture.publicIdPattern.hasMatch(id) ||
        !_key.hasMatch(key) ||
        (frame != 'tension' && frame != 'relaxation') ||
        id != 'exercises/$key-$frame') {
      return null;
    }
    final clean = title is String ? title.replaceAll(_unsafe, ' ').trim() : '';
    return CatalogPicture(
      publicId: id,
      exerciseKey: key,
      frame: frame,
      title: clean.length > 80 ? clean.substring(0, 80) : clean,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CatalogPicture &&
      other.publicId == publicId &&
      other.exerciseKey == exerciseKey &&
      other.frame == frame &&
      other.title == title;

  @override
  int get hashCode => Object.hash(publicId, exerciseKey, frame, title);
}

/// Turns what the member typed into search words (the database matches any
/// of them against `keywords`). Never builds SQL: the words are sent as
/// values of an array filter.
abstract final class CatalogQuery {
  static const maxWords = 5;
  static const maxWordLength = 30;

  /// Lower case, split on anything that isn't a letter or digit (Latin or
  /// Arabic), at most [maxWords] words of at most [maxWordLength]
  /// characters, no duplicates.
  static List<String> words(String text) {
    final out = <String>[];
    for (final w in text.toLowerCase().split(RegExp('[^a-z0-9؀-ۿ]+'))) {
      if (w.isEmpty || w.length > maxWordLength || out.contains(w)) continue;
      out.add(w);
      if (out.length == maxWords) break;
    }
    return out;
  }
}
