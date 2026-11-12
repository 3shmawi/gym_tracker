import 'dart:io';

import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/move/data/datasources/flame_move_sounds.dart';
import 'package:gym_tracker/features/move/domain/repositories/move_sounds.dart';

void main() {
  test('never takes audio focus on Android: music keeps playing', () {
    final android = FlameMoveSounds.context.android;
    expect(android.audioFocus, AndroidAudioFocus.none);
    expect(android.usageType, AndroidUsageType.game);
    expect(android.stayAwake, isFalse);
  });

  test('iOS: ambient (mixes with music, the silent switch mutes it)', () {
    final ios = FlameMoveSounds.context.iOS;
    expect(ios.category, AVAudioSessionCategory.ambient);
    expect(ios.options, isNot(contains(AVAudioSessionOptions.duckOthers)));
  });

  test('the sounds are small, short, mono WAV files', () {
    for (final name in [
      FlameMoveSounds.repFile,
      FlameMoveSounds.milestoneFile,
    ]) {
      final file = File('assets/audio/$name');
      expect(file.existsSync(), isTrue, reason: name);
      final bytes = file.readAsBytesSync();
      expect(bytes.length, lessThan(40 * 1024), reason: name);
      final data = ByteData.sublistView(bytes);
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
      final channels = data.getUint16(22, Endian.little);
      final rate = data.getUint32(24, Endian.little);
      expect(channels, 1);
      final seconds = (bytes.length - 44) / (rate * 2);
      expect(seconds, lessThan(0.5), reason: name);
    }
  });

  test('silent sounds do nothing and never fail', () async {
    const s = SilentMoveSounds();
    await s.load();
    s
      ..rep()
      ..milestone();
    await s.dispose();
  });

  test('playing before loading or after disposing does nothing', () async {
    final s = FlameMoveSounds()
      ..rep()
      ..milestone();
    await s.dispose();
    s.rep();
  });
}
