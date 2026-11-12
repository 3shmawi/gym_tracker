import 'dart:async';

import 'package:flame_audio/flame_audio.dart';
import 'package:gym_tracker/core/monitoring/monitoring.dart';
import 'package:gym_tracker/features/move/domain/repositories/move_sounds.dart';

/// The game's sounds through `flame_audio` (assets/audio/move_*.wav, our
/// own tones from scripts/move_sounds.py, CC0).
///
/// They mix with whatever is playing: iOS uses the ambient category (the
/// silent switch mutes them, music keeps playing), Android asks for no
/// audio focus (music is never paused or lowered).
class FlameMoveSounds implements MoveSounds {
  new();

  static const repFile = 'move_rep.wav';
  static const milestoneFile = 'move_five.wav';

  /// The iOS part is ignored on Android, and the other way round.
  static final AudioContext context = AudioContext(
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.none,
    ),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );

  AudioPool? _rep;
  AudioPool? _milestone;
  Future<void>? _loading;
  bool _disposed = false;
  bool _reported = false;

  @override
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final rep = await FlameAudio.createPool(
        repFile,
        maxPlayers: 3,
        audioContext: context,
      );
      final milestone = await FlameAudio.createPool(
        milestoneFile,
        maxPlayers: 1,
        audioContext: context,
      );
      if (_disposed) {
        unawaited(rep.dispose());
        unawaited(milestone.dispose());
        return;
      }
      _rep = rep;
      _milestone = milestone;
    } on Object catch (e, st) {
      _report(e, st);
    }
  }

  @override
  void rep() => _play(_rep);

  @override
  void milestone() => _play(_milestone);

  void _play(AudioPool? pool) {
    if (pool == null || _disposed) return;
    unawaited(pool.start(volume: 0.8).then<void>((_) {}, onError: _report));
  }

  /// A sound that can't play is not worth more than one report.
  void _report(Object e, [StackTrace? st]) {
    if (_reported) return;
    _reported = true;
    unawaited(Monitoring.captureException(e, st ?? StackTrace.current));
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final rep = _rep;
    final milestone = _milestone;
    _rep = null;
    _milestone = null;
    await rep?.dispose();
    await milestone?.dispose();
  }
}
