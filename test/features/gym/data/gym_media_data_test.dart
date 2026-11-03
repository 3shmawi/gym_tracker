import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/data/repositories/in_memory_gym_media.dart';
import 'package:gym_tracker/features/gym/data/repositories/prefs_gym_media_store.dart';
import 'package:gym_tracker/features/gym/data/repositories/supabase_gym_media_repository.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_media.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_media_repository.dart';
import 'package:gym_tracker/features/gym/domain/usecases/sync_gym_media.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Client extends Mock implements SupabaseClient;

const gymId = 'd0000000-0000-4000-8000-00000000000a';

Map<String, Object?> row(String exercise, String publicId, int position) => {
  'exercise_id': exercise,
  'public_id': publicId,
  'position': position,
};

GymExercisePicture pic(String exercise, String publicId, int position) =>
    GymExercisePicture(
      exerciseId: exercise,
      publicId: publicId,
      position: position,
    );

class _Remote implements GymMediaRepository {
  new(this.answer);

  Result<GymMedia> answer;
  int calls = 0;

  @override
  Future<Result<GymMedia>> fetch(String gymId) async {
    calls++;
    return answer;
  }
}

void main() {
  group(GymExercisePicture, () {
    test('reads a valid row and its exercise key and frame', () {
      final p = GymExercisePicture.tryParse(
        row('flat_db_press', 'exercises/ek-0055-tension', 1),
      )!;
      expect(p.exerciseKey, 'ek-0055');
      expect(p.frame, 'tension');
      expect(
        GymExercisePicture.tryParse(
          row('ex-m3k9w2a1b-2', 'exercises/ek-0055-relaxation', 6),
        ),
        isNotNull,
      );
    });

    final hostile = <String, Object?>{
      'not a map': 'x',
      'null': null,
      'missing position': {'exercise_id': 'a', 'public_id': 'exercises/ek-1'},
      'position as text': row('a', 'exercises/ek-1', 1)..['position'] = '1',
      'position 0': row('a', 'exercises/ek-1', 0),
      'position 7': row('a', 'exercises/ek-1', 7),
      'URL as public id': row('a', 'https://evil.example/x.png', 1),
      'path traversal id': row('a', 'exercises/../x', 1),
      'other folder': row('a', 'avatars/ek-1', 1),
      'upper-case exercise': row('Flat', 'exercises/ek-1', 1),
      'injection exercise': row("x'; drop table", 'exercises/ek-1', 1),
      'Cyrillic exercise': row('ех_press', 'exercises/ek-1', 1),
      'too long exercise': row('a' * 65, 'exercises/ek-1', 1),
      'empty plan id': row('ex-', 'exercises/ek-1', 1),
      'exercise as number': row('a', 'exercises/ek-1', 1)..['exercise_id'] = 5,
    };
    for (final MapEntry(key: name, value: json) in hostile.entries) {
      test('drops a bad row: $name', () {
        expect(GymExercisePicture.tryParse(json), isNull);
      });
    }

    test('a public id outside ek-<id>-<frame> has no key or frame', () {
      final p = pic('a', 'exercises/other-name', 1);
      expect(p.exerciseKey, isNull);
      expect(p.frame, isNull);
    });
  });

  group(GymMedia, () {
    test('orders by position and keeps the database limits', () {
      final media = GymMedia.fromPictures([
        pic('a', 'exercises/ek-3', 3),
        pic('a', 'exercises/ek-1', 1),
        pic('a', 'exercises/ek-1', 2), // same picture twice
        pic('a', 'exercises/ek-9', 1), // same position twice
        pic('a', 'exercises/ek-2', 2),
        pic('a', 'exercises/ek-4', 4),
        pic('a', 'exercises/ek-5', 5),
        pic('a', 'exercises/ek-6', 6),
        pic('b', 'exercises/ek-1', 1),
      ]);
      expect(media.picturesFor('a').map((p) => p.publicId), [
        for (var i = 1; i <= 6; i++) 'exercises/ek-$i',
      ]);
      expect(media.picturesFor('b'), hasLength(1));
      expect(media.picturesFor('unknown'), isEmpty);
    });

    test('never more than 1200 pictures in all', () {
      final media = GymMedia.fromPictures([
        for (var e = 0; e < 210; e++)
          for (var p = 1; p <= 6; p++) pic('e$e', 'exercises/ek-$p', p),
      ]);
      expect(media.allPictures, hasLength(GymMedia.maxRows));
    });

    test('round-trips through its JSON and drops what is malformed', () {
      final media = GymMedia.fromPictures([
        pic('a', 'exercises/ek-1-tension', 1),
        pic('a', 'exercises/ek-1-relaxation', 2),
      ]);
      expect(GymMedia.fromJson(media.toJson()), media);
      final json = media.toJson();
      (json['pictures']! as List).add({'exercise_id': '../x'});
      expect(GymMedia.fromJson(json), media);
      expect(
        GymMedia.fromJson(const {'v': 2, 'pictures': <Object>[]}),
        GymMedia.empty,
      );
      expect(GymMedia.fromJson('garbage'), GymMedia.empty);
      expect(
        GymMedia.fromJson(const {'v': 1, 'pictures': 'x'}),
        GymMedia.empty,
      );
    });
  });

  group(SupabaseGymMediaRepository, () {
    SupabaseGymMediaRepository repo(List<Object?> rows) =>
        SupabaseGymMediaRepository(
          _Client(),
          retries: 0,
          readRows: (_) async => rows,
        );

    test('reads the rows, dropping any outside the rules', () async {
      final r = await repo([
        row('flat_db_press', 'exercises/ek-0055-tension', 1),
        row('flat_db_press', 'exercises/ek-0055-relaxation', 2),
        row('flat_db_press', 'https://evil.example/x.png', 3),
        'not a row',
      ]).fetch(gymId);
      final media = (r as Success<GymMedia>).value;
      expect(media.picturesFor('flat_db_press'), hasLength(2));
    });

    test('an empty table is empty media, not a failure', () async {
      final r = await repo(const []).fetch(gymId);
      expect((r as Success<GymMedia>).value.isEmpty, isTrue);
    });

    test('a crafted gym id never reaches the server', () async {
      var asked = false;
      final r = await SupabaseGymMediaRepository(
        _Client(),
        retries: 0,
        readRows: (_) async {
          asked = true;
          return const [];
        },
      ).fetch("x' or 1=1 --");
      expect(r, isA<Failed<GymMedia>>());
      expect(asked, isFalse);
    });

    test('a network error is a failure, never a throw', () async {
      final r = await SupabaseGymMediaRepository(
        _Client(),
        retries: 0,
        readRows: (_) async => throw const SocketLikeException(),
      ).fetch(gymId);
      expect(r, isA<Failed<GymMedia>>());
    });
  });

  group(PrefsGymMediaStore, () {
    Future<PrefsGymMediaStore> store([Map<String, Object> v = const {}]) {
      SharedPreferences.setMockInitialValues(v);
      return SharedPreferences.getInstance().then(PrefsGymMediaStore.new);
    }

    final media = GymMedia.fromPictures([
      pic('flat_db_press', 'exercises/ek-0055-tension', 1),
    ]);

    test('saves, loads and clears a gym copy', () async {
      final s = await store();
      await s.save(gymId, media);
      expect((await s.load(gymId) as Success<GymMedia?>).value, media);
      await s.clear(gymId);
      expect((await s.load(gymId) as Success<GymMedia?>).value, isNull);
    });

    test('a broken copy loads as nothing or as what is valid', () async {
      var s = await store({PrefsGymMediaStore.key(gymId): '{not json'});
      expect((await s.load(gymId) as Success<GymMedia?>).value, isNull);
      s = await store({
        PrefsGymMediaStore.key(gymId): jsonEncode({
          'v': 1,
          'pictures': [
            row('flat_db_press', 'exercises/ek-0055-tension', 1),
            row('../x', 'exercises/ek-1', 1),
          ],
        }),
      });
      expect((await s.load(gymId) as Success<GymMedia?>).value, media);
    });

    test('a crafted gym id is never used as a key', () async {
      final s = await store();
      expect(await s.save('../../x', media), isA<Failed<void>>());
      expect((await s.load('a b') as Success<GymMedia?>).value, isNull);
    });
  });

  group(SyncGymMedia, () {
    final media = GymMedia.fromPictures([
      pic('flat_db_press', 'exercises/ek-0055-tension', 1),
    ]);

    test('the server wins and is kept for offline', () async {
      final store = InMemoryGymMediaStore();
      final r = await SyncGymMedia(_Remote(Success(media)), store)(gymId);
      expect(r.media, media);
      expect(r.changed, isTrue);
      expect((await store.load(gymId) as Success<GymMedia?>).value, media);
      final again = await SyncGymMedia(_Remote(Success(media)), store)(gymId);
      expect(again.changed, isFalse);
    });

    test('offline: the phone copy, no change, no error', () async {
      final store = InMemoryGymMediaStore();
      await store.save(gymId, media);
      final r = await SyncGymMedia(
        _Remote(const Failed(NetworkFailure())),
        store,
      )(gymId);
      expect(r.media, media);
      expect(r.changed, isFalse);
    });

    test('offline with nothing saved: empty (bundled pictures show)', () async {
      final r = await SyncGymMedia(
        _Remote(const Failed(TimeoutFailure())),
        InMemoryGymMediaStore(),
      )(gymId);
      expect(r.media.isEmpty, isTrue);
    });

    test('the captain removed every picture: the copy is cleared', () async {
      final store = InMemoryGymMediaStore();
      await store.save(gymId, media);
      final r = await SyncGymMedia(
        _Remote(const Success(GymMedia.empty)),
        store,
      )(gymId);
      expect(r.changed, isTrue);
      expect((await store.load(gymId) as Success<GymMedia?>).value, isNull);
    });
  });
}

class SocketLikeException implements Exception {
  const new();
}
