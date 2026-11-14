import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/data/repositories/file_gym_logo_store.dart';
import 'package:gym_tracker/features/gym/data/repositories/in_memory_gym_logos.dart';
import 'package:gym_tracker/features/gym/data/repositories/prefs_gym_local_repository.dart';
import 'package:gym_tracker/features/gym/data/repositories/supabase_gym_logo_repository.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/gym_logo_fakes.dart';

void main() {
  group(FileGymLogoStore, () {
    late Directory root;
    late SharedPreferences prefs;
    late FileGymLogoStore store;

    Directory logos() =>
        Directory('${root.path}/${FileGymLogoStore.folderName}');
    List<String> files() => logos().existsSync()
        ? (logos().listSync().map((f) => f.uri.pathSegments.last).toList()
            ..sort())
        : const [];

    GymLogoRef ref(String gymId, int version, [String ext = 'png']) =>
        GymLogoRef(
          gymId: gymId,
          path: logoPathOf(gymId, ext),
          version: version,
        );

    setUp(() async {
      root = await Directory.systemTemp.createTemp('azm_logos');
      addTearDown(() => root.delete(recursive: true));
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      store = FileGymLogoStore(prefs, () async => root);
    });

    test('keeps a logo as a file named by gym and version', () async {
      final saved = await store.save(ref(gymA, 7), testLogoPng);
      expect(saved, isA<Success<Object?>>());
      expect(files(), ['$gymA-7.img']);
      final loaded = await store.load();
      expect(loaded[gymA]!.logo, ref(gymA, 7));
      expect(File(loaded[gymA]!.filePath).readAsBytesSync(), testLogoPng);
    });

    test('a new version is a new file; the old one goes', () async {
      await store.save(ref(gymA, 7), testLogoPng);
      final old = (await store.load())[gymA]!.filePath;
      await store.save(ref(gymA, 9, 'jpg'), Uint8List.fromList([1, 2, 3]));
      final now = (await store.load())[gymA]!;
      expect(now.filePath, isNot(old), reason: 'the image cache keys by path');
      expect(now.logo.path, logoPathOf(gymA, 'jpg'));
      expect(files(), ['$gymA-9.img']);
    });

    test('an entry whose file is gone is left out', () async {
      await store.save(ref(gymA, 7), testLogoPng);
      File('${logos().path}/$gymA-7.img').deleteSync();
      expect(await store.load(), isEmpty);
    });

    test(
      'a file left by a crash (no entry, or a .tmp) is swept away',
      () async {
        logos().createSync(recursive: true);
        File('${logos().path}/$gymB-1.img').writeAsBytesSync([1]);
        File('${logos().path}/$gymA-3.img.tmp').writeAsBytesSync([1]);
        await store.save(ref(gymA, 3), testLogoPng);
        expect(files(), ['$gymA-3.img']);
      },
    );

    test('remove and clear delete the files and the index', () async {
      await store.save(ref(gymA, 1), testLogoPng);
      await store.save(ref(gymB, 1), testLogoPng);
      await store.remove(gymA);
      expect((await store.load()).keys, {gymB});
      expect(files(), ['$gymB-1.img']);
      await store.clear();
      expect(await store.load(), isEmpty);
      expect(logos().existsSync(), isFalse);
      expect(prefs.getString(FileGymLogoStore.indexKey), isNull);
    });

    test('a corrupt or hostile index is no logos, never a crash', () async {
      for (final raw in [
        'not json',
        '[]',
        '{"$gymA": "x"}',
        '{"../../etc": {"path": "../../etc/logo.png", "version": 1}}',
        '{"$gymA": {"path": "$gymB/logo.png", "version": 1}}',
        '{"$gymA": {"path": "$gymA/logo.png", "version": -1}}',
        '{"$gymA": {"path": "$gymA/logo.png", "version": "1"}}',
      ]) {
        await prefs.setString(FileGymLogoStore.indexKey, raw);
        expect(await store.load(), isEmpty, reason: raw);
      }
    });

    test('only a UUID and a version reach the file system', () async {
      for (final bad in [
        const GymLogoRef(gymId: '../x', path: 'x', version: 1),
        GymLogoRef(gymId: gymA.toUpperCase(), path: 'x', version: 1),
        GymLogoRef(gymId: gymA, path: logoPathOf(gymA), version: -5),
      ]) {
        expect(await store.save(bad, testLogoPng), isA<Failed<Object?>>());
      }
      expect(files(), isEmpty);
    });

    test('signing out (the gym state cleared) deletes the logos too', () async {
      await store.save(ref(gymA, 1), testLogoPng);
      final local = PrefsGymLocalRepository(prefs, logos: store);
      await local.clear();
      expect(await store.load(), isEmpty);
      expect(files(), isEmpty);
    });
  });

  group(SupabaseGymLogoRepository, () {
    late SupabaseClient client;
    setUp(
      () => client = SupabaseClient(
        'https://example.supabase.co',
        'sb_publishable_test',
      ),
    );

    test('downloads the path with the version as the cache nonce', () async {
      final calls = <(String, String)>[];
      final repo = SupabaseGymLogoRepository(
        client,
        retries: 0,
        download: (path, nonce) async {
          calls.add((path, nonce));
          return testLogoPng;
        },
      );
      final result = await repo.fetch(
        GymLogoRef(gymId: gymA, path: logoPathOf(gymA), version: 42),
      );
      expect((result as Success<Uint8List>).value, testLogoPng);
      expect(calls, [(logoPathOf(gymA), '42')]);
    });

    test("a path outside the gym's folder is never requested", () async {
      var calls = 0;
      final repo = SupabaseGymLogoRepository(
        client,
        retries: 0,
        download: (_, _) async {
          calls++;
          return testLogoPng;
        },
      );
      for (final path in [
        logoPathOf(gymB),
        '$gymA/../$gymB/logo.png',
        '$gymA/logo.svg',
        '',
      ]) {
        expect(
          await repo.fetch(GymLogoRef(gymId: gymA, path: path, version: 1)),
          isA<Failed<Uint8List>>(),
          reason: path,
        );
      }
      expect(calls, 0);
    });

    test('a refused download is a failure, not a throw', () async {
      final repo = SupabaseGymLogoRepository(
        client,
        retries: 0,
        download: (_, _) async =>
            throw const StorageException('Object not found', statusCode: '404'),
      );
      expect(
        await repo.fetch(
          GymLogoRef(gymId: gymA, path: logoPathOf(gymA), version: 1),
        ),
        isA<Failed<Uint8List>>(),
      );
    });
  });

  test('without a backend, no logo downloads and nothing throws', () async {
    expect(
      await const UnconfiguredGymLogoRepository().fetch(
        GymLogoRef(gymId: gymA, path: logoPathOf(gymA), version: 1),
      ),
      isA<Failed<Uint8List>>(),
    );
  });
}
