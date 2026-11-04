import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/data/repositories/supabase_picture_catalog_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Client extends Mock implements SupabaseClient;

void main() {
  final client = _Client();

  test('empty words: no request', () async {
    var calls = 0;
    final repo = SupabasePictureCatalogRepository(
      client,
      readRows: (_) async {
        calls++;
        return [];
      },
    );
    expect(await repo.search(const []), isA<Success<Object?>>());
    expect(calls, 0);
  });

  test('words that were not cleaned are refused, never sent', () async {
    var calls = 0;
    final repo = SupabasePictureCatalogRepository(
      client,
      retries: 0,
      readRows: (_) async {
        calls++;
        return [];
      },
    );
    for (final words in [
      ['Chest'],
      ['a,b'],
      ['{x}'],
      ['a', 'b', 'c', 'd', 'e', 'f'],
    ]) {
      expect(
        await repo.search(words),
        isA<Failed<Object?>>(),
        reason: '$words',
      );
    }
    expect(calls, 0);
  });

  test('bad rows are dropped', () async {
    final repo = SupabasePictureCatalogRepository(
      client,
      readRows: (words) async => [
        {
          'public_id': 'exercises/ek-0055-tension',
          'exercise_key': 'ek-0055',
          'frame': 'tension',
          'title_en': 'Press',
        },
        {'public_id': 'https://evil.example/x.png'},
        'junk',
      ],
    );
    final result = await repo.search(const ['chest']);
    expect((result as Success).value, hasLength(1));
  });
}
