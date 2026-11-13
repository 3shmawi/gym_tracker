import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/move/domain/entities/move_sound_mode.dart';

void main() {
  test('ids are stable; anything unknown is the default (voice)', () {
    expect(MoveSoundMode.values.map((m) => m.id), ['voice', 'tones', 'off']);
    for (final odd in <Object?>[null, '', 'loud', 7, 'Voice', true]) {
      expect(MoveSoundMode.fromId(odd), MoveSoundMode.voice, reason: '$odd');
    }
    for (final m in MoveSoundMode.values) {
      expect(MoveSoundMode.fromId(m.id), m);
    }
  });

  test('the button cycles voice → tones → off → voice', () {
    var m = MoveSoundMode.voice;
    final seen = <MoveSoundMode>[];
    for (var i = 0; i < 3; i++) {
      m = m.next(voiceAvailable: true);
      seen.add(m);
    }
    expect(seen, [MoveSoundMode.tones, MoveSoundMode.off, MoveSoundMode.voice]);
  });

  test('without a voice the button skips it', () {
    expect(MoveSoundMode.off.next(voiceAvailable: false), MoveSoundMode.tones);
    expect(
      MoveSoundMode.voice.next(voiceAvailable: false),
      MoveSoundMode.tones,
    );
  });

  test('the voice falls back to tones when the phone has none', () {
    expect(
      MoveSoundMode.voice.effective(voiceAvailable: false),
      MoveSoundMode.tones,
    );
    expect(
      MoveSoundMode.voice.effective(voiceAvailable: true),
      MoveSoundMode.voice,
    );
    expect(
      MoveSoundMode.off.effective(voiceAvailable: false),
      MoveSoundMode.off,
    );
  });
}
