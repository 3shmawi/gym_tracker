import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/gym/data/repositories/in_memory_gym_logos.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/usecases/gym_logo_check.dart';
import 'package:gym_tracker/features/gym/domain/usecases/sync_gym_logos.dart';

import '../../../helpers/gym_fakes.dart';
import '../../../helpers/gym_logo_fakes.dart';

/// PNG bytes with the given header (the pixels are never read).
Uint8List png(int width, int height, {bool animated = false, int pad = 0}) {
  List<int> u32(int v) => [v >> 24 & 255, v >> 16 & 255, v >> 8 & 255, v & 255];
  List<int> chunk(String type, List<int> data) => [
    ...u32(data.length),
    ...type.codeUnits,
    ...data,
    0, 0, 0, 0, // CRC: not checked.
  ];
  return Uint8List.fromList([
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    ...chunk('IHDR', [...u32(width), ...u32(height), 8, 6, 0, 0, 0]),
    if (animated) ...chunk('acTL', [...u32(2), ...u32(0)]),
    ...chunk('IDAT', List.filled(4 + pad, 0)),
    ...chunk('IEND', const []),
  ]);
}

/// JPEG bytes: SOI, an APP0 segment, then a baseline frame header.
Uint8List jpeg(int width, int height) => Uint8List.fromList([
  0xFF,
  0xD8,
  0xFF,
  0xE0,
  0x00,
  0x10,
  ...'JFIF'.codeUnits,
  0,
  1,
  1,
  0,
  0,
  1,
  0,
  1,
  0,
  0,
  0xFF,
  0xC0,
  0x00,
  0x11,
  8,
  height >> 8,
  height & 255,
  width >> 8,
  width & 255,
  3,
  1,
  0x22,
  0,
  2,
  0x11,
  1,
  3,
  0x11,
  1,
  0xFF,
  0xDA,
  0x00,
  0x02,
  0xFF,
  0xD9,
]);

void main() {
  group('Gym logo fields', () {
    Map<String, Object?> json({Object? path, Object? version}) => {
      'id': gymA,
      'name': 'Iron House',
      'logo_path': path,
      'logo_updated_at': version,
    };

    test("a logo in the gym's own folder, with its version", () {
      final gym = Gym.fromJson(
        json(path: logoPathOf(gymA), version: '2026-11-14T12:00:00+00:00'),
      );
      expect(gym.logoPath, '$gymA/logo.png');
      expect(gym.logoVersion, DateTime.utc(2026, 11, 14, 12));
      expect(
        gym.logo,
        GymLogoRef(
          gymId: gymA,
          path: '$gymA/logo.png',
          version: DateTime.utc(2026, 11, 14, 12).millisecondsSinceEpoch,
        ),
      );
      for (final ext in ['png', 'jpg', 'jpeg']) {
        expect(Gym.readLogoPath(gymA, '$gymA/logo.$ext'), isNotNull);
      }
    });

    test('anything else is "no logo", never an error', () {
      for (final path in <Object?>[
        null,
        '',
        logoPathOf(gymB), // Another gym's folder.
        '$gymA/logo.svg',
        '$gymA/logo.gif',
        '$gymA/LOGO.PNG',
        '$gymA/../$gymB/logo.png',
        '../$gymA/logo.png',
        '/$gymA/logo.png',
        '$gymA/logo.png\n',
        '$gymA/logo.png?x=1',
        '$gymA/logo.png#',
        '$gymA//logo.png',
        '${gymA.toUpperCase()}/logo.png',
        "$gymA/logo.png'; drop table gyms;--",
        '$gymA/${'a' * 300}.png',
        'a' * 100000,
        42,
        ['$gymA/logo.png'],
        {'path': '$gymA/logo.png'},
      ]) {
        final gym = Gym.fromJson(json(path: path));
        expect(gym.logoPath, isNull, reason: '$path');
        expect(gym.logo, isNull, reason: '$path');
      }
    });

    test('a bad version is no version; the logo still shows (version 0)', () {
      for (final v in <Object?>[null, '', 'yesterday', 12, '9' * 100]) {
        final gym = Gym.fromJson(json(path: logoPathOf(gymA), version: v));
        expect(gym.logoVersion, isNull, reason: '$v');
        expect(gym.logo?.version, 0, reason: '$v');
      }
    });

    test('a new logo is not a new gym: == and hashCode leave it out', () {
      final before = Gym.fromJson(json());
      final after = Gym.fromJson(
        json(path: logoPathOf(gymA), version: '2026-11-14T12:00:00Z'),
      );
      expect(after, before);
      expect(after.hashCode, before.hashCode);
    });

    test("kept in the phone's copy, and an old copy reads as no logo", () {
      final m = member(
        gymId: gymA,
        logoPath: logoPathOf(gymA),
        logoVersion: DateTime.utc(2026, 11, 14),
      );
      final back = Membership.fromJson(m.toJson());
      expect(back.gym.logoPath, m.gym.logoPath);
      expect(back.gym.logoVersion, m.gym.logoVersion);

      final old = m.toJson();
      (old['gym']! as Map<String, Object?>)
        ..remove('logo_path')
        ..remove('logo_updated_at');
      expect(Membership.fromJson(old).gym.logo, isNull);
    });

    test('the join answer carries the logo', () {
      final joined = JoinedGym.fromJson({
        'membership_id': 'm1',
        'gym': json(path: logoPathOf(gymA), version: '2026-11-14T12:00:00Z'),
        'role': 'trainee',
      });
      expect(joined.gym.logoPath, logoPathOf(gymA));
      expect(joined.gym.logoVersion, isNotNull);
    });
  });

  group(GymLogoCheck, () {
    test('PNG and JPEG logos of a normal size pass', () {
      expect(GymLogoCheck.inspect(png(512, 512)), isNull);
      expect(GymLogoCheck.inspect(png(16, 2048)), isNull);
      expect(GymLogoCheck.inspect(jpeg(300, 200)), isNull);
      expect(GymLogoCheck.inspect(testLogoPng), isNull, reason: 'a real one');
    });

    test('hostile or broken bytes are refused before any decode', () {
      final cases = <String, (Uint8List, GymLogoProblem)>{
        'empty': (Uint8List(0), GymLogoProblem.empty),
        '513 KB': (
          png(64, 64, pad: GymLogoCheck.maxBytes),
          GymLogoProblem.tooBig,
        ),
        'a GIF': (
          Uint8List.fromList('GIF89a'.codeUnits + List.filled(40, 0)),
          GymLogoProblem.notPngOrJpeg,
        ),
        'an SVG': (
          Uint8List.fromList(
            '<svg xmlns="http://www.w3.org/2000/svg"/>'.codeUnits,
          ),
          GymLogoProblem.notPngOrJpeg,
        ),
        'text': (
          Uint8List.fromList('hello'.codeUnits),
          GymLogoProblem.notPngOrJpeg,
        ),
        'a cut PNG': (
          Uint8List.sublistView(png(64, 64), 0, 30),
          GymLogoProblem.broken,
        ),
        'a PNG with no image data': (
          Uint8List.sublistView(png(64, 64), 0, 33),
          GymLogoProblem.broken,
        ),
        'a PNG chunk longer than the file': (
          Uint8List.fromList([
            ...Uint8List.sublistView(png(64, 64), 0, 33),
            0x7F,
            0xFF,
            0xFF,
            0xFF,
            ...'tEXt'.codeUnits,
          ]),
          GymLogoProblem.broken,
        ),
        'a 20 000 × 20 000 bomb': (png(20000, 20000), GymLogoProblem.badSize),
        'a 4 billion px side': (png(0xFFFFFFFF, 64), GymLogoProblem.badSize),
        'too small': (png(8, 8), GymLogoProblem.badSize),
        'zero': (png(0, 0), GymLogoProblem.badSize),
        'animated': (png(64, 64, animated: true), GymLogoProblem.animated),
        'a JPEG bomb': (jpeg(20000, 20000), GymLogoProblem.badSize),
        'a cut JPEG': (
          Uint8List.sublistView(jpeg(64, 64), 0, 12),
          GymLogoProblem.broken,
        ),
        'a JPEG with no frame': (
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xDA, 0, 2, 0xFF, 0xD9]),
          GymLogoProblem.broken,
        ),
      };
      for (final MapEntry(:key, value: (bytes, problem)) in cases.entries) {
        expect(GymLogoCheck.inspect(bytes), problem, reason: key);
      }
    });
  });

  group(SyncGymLogos, () {
    final v1 = DateTime.utc(2026, 11);
    final v2 = DateTime.utc(2026, 11, 14);

    Membership withLogo(
      String gymId, {
      DateTime? version,
      String ext = 'png',
      MembershipStatus status = MembershipStatus.active,
    }) => member(
      id: 'm-$gymId',
      gymId: gymId,
      status: status,
      logoPath: logoPathOf(gymId, ext),
      logoVersion: version ?? v1,
    );

    test(
      'downloads a new logo once, then skips it while it is the same',
      () async {
        final remote = FakeGymLogoRepository({logoPathOf(gymA): testLogoPng});
        final store = InMemoryGymLogoStore();
        final sync = SyncGymLogos(remote, store);
        expect(await sync([withLogo(gymA)]), isTrue);
        expect(store.bytesOf(gymA), testLogoPng);
        expect(await sync([withLogo(gymA)]), isFalse);
        expect(remote.fetched, hasLength(1));
      },
    );

    test('a logo replaced at the same path is downloaded again', () async {
      final remote = FakeGymLogoRepository({logoPathOf(gymA): testLogoPng});
      final store = InMemoryGymLogoStore();
      final sync = SyncGymLogos(remote, store);
      await sync([withLogo(gymA)]);
      expect(await sync([withLogo(gymA, version: v2)]), isTrue);
      expect(remote.fetched, hasLength(2));
      expect(
        (await store.load())[gymA]!.logo.version,
        v2.millisecondsSinceEpoch,
      );
    });

    test('a removed logo, an ended or a gone membership: deleted', () async {
      final remote = FakeGymLogoRepository({
        logoPathOf(gymA): testLogoPng,
        logoPathOf(gymB): testLogoPng,
      });
      final store = InMemoryGymLogoStore();
      final sync = SyncGymLogos(remote, store);
      await sync([withLogo(gymA), withLogo(gymB)]);
      expect((await store.load()).keys, {gymA, gymB});

      expect(
        await sync([
          member(id: 'm-a', gymId: gymA), // Logo removed.
          withLogo(gymB, status: MembershipStatus.ended),
        ]),
        isTrue,
      );
      expect(await store.load(), isEmpty);
    });

    test('offline: what the phone has stays; tried again next time', () async {
      final remote = FakeGymLogoRepository({logoPathOf(gymA): testLogoPng});
      final store = InMemoryGymLogoStore();
      final sync = SyncGymLogos(remote, store);
      await sync([withLogo(gymA)]);
      remote.online = false;
      expect(await sync([withLogo(gymA, version: v2)]), isFalse);
      expect(
        (await store.load())[gymA]!.logo.version,
        v1.millisecondsSinceEpoch,
      );
      remote.online = true;
      expect(await sync([withLogo(gymA, version: v2)]), isTrue);
    });

    test('refused bytes are never kept, and the reason is told', () async {
      final remote = FakeGymLogoRepository({
        logoPathOf(gymA): png(20000, 20000),
      });
      final store = InMemoryGymLogoStore();
      final refused = <GymLogoProblem>[];
      final sync = SyncGymLogos(remote, store, onRefused: refused.add);
      expect(await sync([withLogo(gymA)]), isFalse);
      expect(await store.load(), isEmpty);
      expect(refused, [GymLogoProblem.badSize]);
    });

    test('at most ${SyncGymLogos.maxLogos} logos on the phone', () async {
      final ids = [
        for (var i = 0; i < 15; i++)
          'd0000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
      ];
      final remote = FakeGymLogoRepository({
        for (final id in ids) logoPathOf(id): testLogoPng,
      });
      final store = InMemoryGymLogoStore();
      await SyncGymLogos(remote, store)([for (final id in ids) withLogo(id)]);
      expect(
        (await store.load()).keys,
        ids.take(SyncGymLogos.maxLogos).toSet(),
      );
    });
  });
}
