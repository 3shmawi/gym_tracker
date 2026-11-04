import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/data/repositories/in_memory_gym_media.dart';
import 'package:gym_tracker/features/gym/domain/entities/catalog_picture.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_media.dart';
import 'package:gym_tracker/features/gym/domain/usecases/solo_pictures.dart';

String pic(int n, [String frame = 'tension']) =>
    'exercises/ek-${n.toString().padLeft(4, '0')}-$frame';

void main() {
  late InMemoryGymMediaStore store;
  late SoloPictures solo;
  setUp(() {
    store = InMemoryGymMediaStore();
    solo = SoloPictures(store);
  });

  test('chosen pictures are kept in order, first = cover', () async {
    await solo.choose('flat_db_press', [pic(2), pic(1)]);
    final mine = (await solo.load()).picturesFor('flat_db_press');
    expect(
      [for (final p in mine) (p.publicId, p.position)],
      [(pic(2), 1), (pic(1), 2)],
    );
  });

  test('another exercise is left alone; empty removes', () async {
    await solo.choose('flat_db_press', [pic(1)]);
    await solo.choose('pec_deck', [pic(9)]);
    await solo.choose('flat_db_press', const []);
    final media = await solo.load();
    expect(media.picturesFor('flat_db_press'), isEmpty);
    expect(media.picturesFor('pec_deck'), hasLength(1));
  });

  test('at most 6, no duplicates, invalid ids dropped', () async {
    final result = await solo.choose('flat_db_press', [
      pic(1),
      pic(1),
      'https://evil.example/x.png',
      '../../etc/passwd',
      '',
      for (var i = 2; i <= 9; i++) pic(i),
    ]);
    final mine = (result as Success<GymMedia>).value.picturesFor(
      'flat_db_press',
    );
    expect(mine, hasLength(6));
    expect(mine.first.publicId, pic(1));
  });

  test('a hostile exercise id is refused, nothing saved', () async {
    for (final id in ['', '<script>', "x'; drop table --", 'a' * 200]) {
      expect(await solo.choose(id, [pic(1)]), isA<Failed<Object?>>());
    }
    expect((await solo.load()).isEmpty, isTrue);
  });

  test('kept apart from any gym (its own key)', () async {
    await solo.choose('flat_db_press', [pic(1)]);
    expect(SoloPictures.storeId, isNot(matches(RegExp(r'^[0-9a-f-]{36}$'))));
  });

  group(CatalogQuery, () {
    test('lower case words, Latin and Arabic, no duplicates', () {
      expect(CatalogQuery.words('Flat  DUMBBELL press, flat'), [
        'flat',
        'dumbbell',
        'press',
      ]);
      expect(CatalogQuery.words('صدر دمبل'), ['صدر', 'دمبل']);
    });

    test('injection-like text becomes plain words', () {
      expect(CatalogQuery.words("chest'); drop table x; --"), [
        'chest',
        'drop',
        'table',
        'x',
      ]);
      expect(CatalogQuery.words(r'{a,b} %00 \u0000'), [
        'a',
        'b',
        '00',
        'u0000',
      ]);
    });

    test('limits: 5 words, none longer than 30', () {
      expect(CatalogQuery.words('a b c d e f g'), hasLength(5));
      expect(CatalogQuery.words('x' * 31), isEmpty);
      expect(CatalogQuery.words('   '), isEmpty);
    });
  });

  group('CatalogPicture.tryParse', () {
    Map<String, Object?> row({
      Object? id = 'exercises/ek-0055-tension',
      Object? key = 'ek-0055',
      Object? frame = 'tension',
      Object? title = 'Dumbbell Bench Press',
    }) => {
      'public_id': id,
      'exercise_key': key,
      'frame': frame,
      'title_en': title,
    };

    test('a good row', () {
      final p = CatalogPicture.tryParse(row())!;
      expect(
        (p.exerciseKey, p.frame, p.title),
        ('ek-0055', 'tension', 'Dumbbell Bench Press'),
      );
    });

    test('rows outside the rules are dropped', () {
      for (final bad in [
        row(id: 'https://evil.example/a.png'),
        row(id: 'exercises/ek-0056-tension'), // not its key
        row(frame: 'middle'),
        row(key: 'EK-1'),
        row(id: 42),
        'not a map',
        null,
      ]) {
        expect(CatalogPicture.tryParse(bad), isNull, reason: '$bad');
      }
    });

    test('titles: no bidi overrides, at most 80 characters', () {
      final p = CatalogPicture.tryParse(row(title: 'Press\u202E${'x' * 100}'))!;
      expect(p.title.contains('\u202E'), isFalse);
      expect(p.title.length, 80);
      expect(CatalogPicture.tryParse(row(title: 7))!.title, '');
    });
  });
}
