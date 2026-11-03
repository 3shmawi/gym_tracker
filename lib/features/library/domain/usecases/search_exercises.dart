import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/features/workout/domain/usecases/plan_rules.dart';

/// Finds library exercises by what the member types, the muscle and the
/// equipment. Typed text is untrusted: it is cleaned, cut to a sane length
/// and only ever compared, never run or stored.
class SearchExercises {
  const new();

  /// Characters of the query that count; the rest is ignored.
  static const maxQueryLength = 60;

  static final _diacritics = RegExp('[ً-ٰٟـ]');

  /// [text] in a form that matches across spellings: lower case, no Arabic
  /// diacritics or tatweel, alef / yaa / taa marbuta variants unified, runs
  /// of spaces as one.
  static String normalize(String text) =>
      PlanNames.clean(text)
          .toLowerCase()
          .replaceAll(_diacritics, '')
          .replaceAll(RegExp('[أإآٱ]'), 'ا')
          .replaceAll('ى', 'ي')
          .replaceAll('ة', 'ه')
          .replaceAll('ؤ', 'و')
          .replaceAll('ئ', 'ي');

  /// The exercises of [all] that fit, in the library's order with names that
  /// start with the query first. Every word of the query must appear in one
  /// of the two names.
  List<LibraryExercise> call(
    List<LibraryExercise> all, {
    String query = '',
    MuscleGroup? muscle,
    Equipment? equipment,
  }) {
    final cut = query.runes.take(maxQueryLength);
    final words = normalize(String.fromCharCodes(cut))
        .split(' ')
        .where((w) => w.isNotEmpty)
        .toList();
    final hits = <(LibraryExercise, bool)>[];
    for (final e in all) {
      if (muscle != null && e.muscle != muscle) continue;
      if (equipment != null && !e.equipment.contains(equipment)) continue;
      final names = [normalize(e.name.en), normalize(e.name.ar)];
      final haystack = names.join(' ');
      if (!words.every(haystack.contains)) continue;
      final starts =
          words.isNotEmpty && names.any((n) => n.startsWith(words.first));
      hits.add((e, starts));
    }
    return [
      for (final (e, starts) in hits)
        if (starts) e,
      for (final (e, starts) in hits)
        if (!starts) e,
    ];
  }
}
