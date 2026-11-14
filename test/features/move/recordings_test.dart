import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/move/data/datasources/pose_recording.dart';
import 'package:gym_tracker/features/move/domain/detectors/push_up_detector.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';

/// Real push-up sets (decision 9 of docs/designs/move_games.md), replayed
/// through the real detector: each must give the count a person counted
/// on the video. Recordings are made with tool/pose_record/record.py and
/// listed in test/fixtures/move/push_ups/manifest.json.
void main() {
  const dir = 'test/fixtures/move/push_ups';
  final manifest = jsonDecode(
    File('$dir/manifest.json').readAsStringSync(),
  ) as Map<String, Object?>;
  final entries = (manifest['recordings']! as List<Object?>)
      .cast<Map<String, Object?>>();

  test('the manifest is well formed', () {
    expect(manifest['version'], 1);
    for (final e in entries) {
      expect(e['file'], isA<String>());
      expect(e['reps'], isA<int>(), reason: '${e['file']}');
      expect(
        ['side_left', 'side_right', 'front'],
        contains(e['view']),
        reason: '${e['file']}',
      );
      expect(File('$dir/${e['file']}').existsSync(), isTrue);
    }
  });

  test('only recordings are kept: no videos, no images', () {
    for (final f in Directory('test/fixtures/move').listSync(recursive: true)) {
      if (f is! File) continue;
      expect(f.path, endsWith('.json'), reason: f.path);
      // Joints and times only: nothing else in a recording.
      final root = jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
      if (f.path.endsWith('manifest.json')) continue;
      expect(root.keys.toSet(), {
        'version',
        'aspect',
        'frames',
      }, reason: f.path);
      for (final frame in root['frames']! as List<Object?>) {
        expect((frame! as Map<String, Object?>).keys.toSet(), {
          't',
          'j',
        }, reason: f.path);
      }
    }
  });

  test("the tool's output is what the app reads", () {
    // The shape tool/pose_record/record.py writes (times with a decimal).
    const sample =
        '{"version":1,"aspect":0.5625,"frames":['
        '{"t":0.0,"j":{}},'
        '{"t":66.7,"j":{"leftShoulder":[0.41,0.52,0.98],'
        '"leftWrist":[0.45,0.8,0.97]}}]}';
    final frames = PoseRecording.decode(sample);
    expect(frames, hasLength(2));
    expect(frames.first.joints, isEmpty);
    expect(frames.last.at, const Duration(microseconds: 66700));
    expect(frames.last.joints, hasLength(2));
    expect(frames.last.aspect, 0.5625);
  });

  test("the tool's own tests pass (no video or model needed)", () async {
    final python = await Process.run('python3', [
      '--version',
    ]).then((r) => r.exitCode == 0, onError: (_) => false);
    if (!python) {
      markTestSkipped('python3 not found');
      return;
    }
    final r = await Process.run('python3', [
      '-m',
      'unittest',
      'tool/pose_record/test_record.py',
    ]);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  });

  if (entries.isEmpty) {
    test(
      'real sets count right',
      () {},
      skip:
          'No recordings yet: the owner films 4-6 sets, then '
          'tool/pose_record/record.py (docs/features/move_games.md)',
    );
  }

  for (final e in entries) {
    final file = e['file']! as String;
    test('$file: ${e['reps']} reps (${e['view']})', () {
      final frames = PoseRecording.decode(
        File('$dir/$file').readAsStringSync(),
      );
      expect(frames, isNotEmpty);
      final detector = PushUpDetector();
      final events = [for (final f in frames) ...detector.onFrame(f).events];
      final tolerance = (e['tolerance'] as int?) ?? 0;
      final counted = events.whereType<RepCounted>().length;
      expect(
        (counted - (e['reps']! as int)).abs(),
        lessThanOrEqualTo(tolerance),
        reason: 'counted $counted',
      );
      if (e['half_reps'] case final int half) {
        expect(events.whereType<HalfRep>().length, half);
      }
      if (e['too_fast'] case final int fast) {
        expect(events.whereType<TooFast>().length, fast);
      }
    });
  }
}
