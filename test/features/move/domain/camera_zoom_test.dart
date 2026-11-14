import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/move/data/repositories/prefs_move_local_repository.dart';
import 'package:gym_tracker/features/move/domain/repositories/pose_source.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group(CameraZoom, () {
    test('kept inside what the phone allows, never above 3×', () {
      const z = CameraZoom(min: 0.6, max: 8, level: 0.6);
      expect(z.top, CameraZoom.maxOffered);
      expect(z.at(0.1).level, 0.6);
      expect(z.at(5).level, 3);
      expect(z.at(1.25).level, 1.25);
      expect(z.at(double.nan).level, 0.6);
      expect(z.at(double.infinity).level, 0.6);
      expect(z.at(0.6).atWidest, isTrue);
      expect(z.at(3).atClosest, isTrue);
    });

    test('a phone with no range has nothing to choose', () {
      expect(const CameraZoom(min: 1, max: 1, level: 1).adjustable, isFalse);
      expect(const CameraZoom(min: 1, max: 4, level: 1).adjustable, isTrue);
      expect(const CameraZoom(min: 1, max: 2, level: 1).top, 2);
    });
  });

  group('the saved zoom', () {
    Future<PrefsMoveLocalRepository> repo(Map<String, Object> values) async {
      SharedPreferences.setMockInitialValues(values);
      return PrefsMoveLocalRepository(await SharedPreferences.getInstance());
    }

    test('kept and read back', () async {
      final r = await repo({});
      expect((await r.cameraZoom() as Success<double?>).value, isNull);
      await r.setCameraZoom(1.25);
      expect((await r.cameraZoom() as Success<double?>).value, 1.25);
    });

    test('an odd stored value is no value (the widest)', () async {
      for (final bad in <Object>[0.0, -1.0, 99.0, 'x', true, 2]) {
        final r = await repo({PrefsMoveLocalRepository.zoomKey: bad});
        expect(
          (await r.cameraZoom() as Success<double?>).value,
          isNull,
          reason: '$bad',
        );
      }
      final r = await repo({});
      expect(await r.setCameraZoom(double.nan), isA<Failed<void>>());
    });
  });
}
