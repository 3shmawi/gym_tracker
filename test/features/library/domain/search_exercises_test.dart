import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/library/data/exercise_catalog.dart';
import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/features/library/domain/usecases/search_exercises.dart';

void main() {
  const search = SearchExercises();
  const all = ExerciseCatalog.all;
  List<String> ids(String q, {MuscleGroup? muscle, Equipment? equipment}) =>
      search(
        all,
        query: q,
        muscle: muscle,
        equipment: equipment,
      ).map((e) => e.id).toList();

  test('no query and no filter: everything, in the library order', () {
    expect(ids(''), all.map((e) => e.id));
    expect(ids('   '), all.map((e) => e.id));
  });

  test('English: any word of the name, any case', () {
    expect(ids('pec deck'), ['pec_deck', 'reverse_pec_deck']);
    expect(ids('PEC'), contains('pec_deck'));
    expect(ids('pec'), containsAll(['pec_deck', 'reverse_pec_deck']));
    expect(ids('curl dumbbell'), contains('alternating_db_curl'));
  });

  test(
    'Arabic: spellings that differ by alef, yaa, taa marbuta or tashkeel',
    () {
      expect(ids('فراشه'), containsAll(['pec_deck']));
      expect(ids('فراشة'), containsAll(['pec_deck']));
      expect(ids('دفع دمبل'), contains('flat_db_press'));
      expect(ids('اسكوات'), ['barbell_squat']);
      expect(ids('أسكوات'), ['barbell_squat']);
      expect(ids('بَطن'), ['abs']);
    },
  );

  test('names that start with the query come first', () {
    final r = ids('dumbbell');
    expect(r.first, 'db_shoulder_press');
    // "Flat Dumbbell Press" only contains it: after the ones that start.
    expect(r.indexOf('flat_db_press'), greaterThan(r.indexOf('db_lunge')));
    expect(r, contains('flat_db_press'));
  });

  test('filters by muscle and by equipment, and together', () {
    expect(search(all, muscle: MuscleGroup.core).map((e) => e.id), ['abs']);
    final cables = search(all, equipment: Equipment.cable);
    expect(cables, isNotEmpty);
    expect(cables.every((e) => e.equipment.contains(Equipment.cable)), isTrue);
    final both = search(
      all,
      query: 'pull',
      muscle: MuscleGroup.back,
      equipment: Equipment.cable,
    );
    expect(both.map((e) => e.id), ['straight_arm_pulldown']);
  });

  test('nothing matches: an empty list, not an error', () {
    expect(ids('zzzz'), isEmpty);
    expect(ids('pec', muscle: MuscleGroup.legs), isEmpty);
  });

  test('hostile or odd text is only compared, never run', () {
    for (final q in [
      "'; DROP TABLE plans; --",
      '<script>alert(1)</script>',
      '../../etc/passwd',
      '\u202Efnoitcnuf',
      '🏋️‍♂️' * 40,
      'a' * 5000,
      'ا' * 5000,
      '\x00\x01\x1F',
      r'%s %d {0} ${x}',
      r'(?:a+)+$',
      '.*',
      '[',
    ]) {
      expect(() => search(all, query: q), returnsNormally, reason: q);
      expect(search(all, query: q).length, lessThanOrEqualTo(all.length));
    }
  });

  test('only the first 60 characters of a query count', () {
    final tail = 'x' * 200;
    expect(ids('pec deck$tail'), isEmpty, reason: 'the tail is a word');
    final padded = '${'p' * 59} $tail';
    expect(() => search(all, query: padded), returnsNormally);
  });

  test('normalize unifies the spellings and keeps other text', () {
    expect(SearchExercises.normalize('  Pec   DECK '), 'pec deck');
    expect(SearchExercises.normalize('أإآ'), 'ااا');
    expect(SearchExercises.normalize('فراشة'), 'فراشه');
    expect(SearchExercises.normalize('مُحَمَّد'), 'محمد');
    expect(SearchExercises.normalize('a\u202Eb'), 'a b');
  });
}
