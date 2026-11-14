import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/gym/data/repositories/file_gym_logo_store.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym.dart';
import 'package:gym_tracker/features/gym/domain/usecases/gym_logo_check.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/gym_logo_fakes.dart';

/// Gym logos come from a server row and a file someone uploaded
/// (docs/designs/gym_logo.md §10): nothing in them may reach another gym's
/// folder, the phone's file system, or the image decoder unchecked.
void main() {
  test("a logo path can only name this gym's own logo file", () {
    for (final hostile in [
      '../$gymA/logo.png',
      '$gymA/../$gymB/logo.png',
      '$gymB/logo.png',
      '$gymA/logo.png/../../x',
      '$gymA/logo.png%00.svg',
      '$gymA/logo.svg',
      'https://evil.example/logo.png',
      '//evil.example/$gymA/logo.png',
      '$gymA\\logo.png',
      '$gymA/logo.png\u0000',
      ' $gymA/logo.png',
    ]) {
      expect(Gym.readLogoPath(gymA, hostile), isNull, reason: hostile);
    }
    expect(Gym.readLogoPath('../etc', '../etc/logo.png'), isNull);
  });

  test('only a checked UUID and an integer name a file on the phone', () async {
    final root = await Directory.systemTemp.createTemp('azm_logo_sec');
    addTearDown(() => root.delete(recursive: true));
    SharedPreferences.setMockInitialValues({});
    final store = FileGymLogoStore(
      await SharedPreferences.getInstance(),
      () async => root,
    );
    for (final id in [
      '../../evil',
      '/etc/passwd',
      'a b',
      '',
      gymA.toUpperCase(),
    ]) {
      await store.save(
        GymLogoRef(gymId: id, path: logoPathOf(gymA), version: 1),
        testLogoPng,
      );
    }
    final written = root
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.substring(root.path.length));
    expect(written, isEmpty);
  });

  test('a picture is measured before it is decoded; bombs never are', () {
    Uint8List pngHeader(int w, int h) => Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0,
      0,
      0,
      13,
      ...'IHDR'.codeUnits,
      w >> 24 & 255,
      w >> 16 & 255,
      w >> 8 & 255,
      w & 255,
      h >> 24 & 255,
      h >> 16 & 255,
      h >> 8 & 255,
      h & 255,
      8,
      6,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      ...'IDAT'.codeUnits,
      0,
      0,
      0,
      0,
    ]);
    expect(
      GymLogoCheck.inspect(pngHeader(30000, 30000)),
      GymLogoProblem.badSize,
    );
    expect(GymLogoCheck.inspect(pngHeader(512, 512)), isNull);
    expect(
      GymLogoCheck.inspect(Uint8List(GymLogoCheck.maxBytes + 1)),
      GymLogoProblem.tooBig,
    );
  });
}
