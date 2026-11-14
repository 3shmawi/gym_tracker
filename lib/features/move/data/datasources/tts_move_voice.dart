import 'dart:async';
import 'dart:io';

import 'package:flutter_tts/flutter_tts.dart';
import 'package:gym_tracker/core/monitoring/monitoring.dart';
import 'package:gym_tracker/features/move/domain/repositories/move_voice.dart';

/// The phone's text-to-speech (`flutter_tts`) saying the count.
///
/// - **On the phone only:** on Android only a voice that is installed and
///   needs no network is used ([pickVoice]); iOS voices are on the device.
///   Only the number is ever spoken.
/// - **Music keeps playing:** Android takes no audio focus (`speak` without
///   `focus`); on iOS speech uses the app's ambient session (mixes with
///   music, the silent switch mutes it), like the game's tones.
/// - A new count cuts off one still being spoken (queue flush).
class FlutterTtsMoveVoice implements MoveVoice {
  new({FlutterTts? tts}) : _tts = tts ?? FlutterTts();

  final FlutterTts _tts;
  bool _ready = false;
  bool _disposed = false;
  bool _reported = false;

  /// The voice we prefer per language, then any voice of that language.
  static const preferred = {'ar': 'ar-EG', 'en': 'en-US'};

  /// The best voice in [voices] (the plugin's list of maps) for [language]:
  /// same language, no network, installed; [preferred] region first. Null
  /// when there is none. Pure, so it is tested without a phone.
  static Map<String, String>? pickVoice(Object? voices, String language) {
    if (voices is! List) return null;
    final want = language.toLowerCase();
    final found = <Map<String, String>>[];
    for (final v in voices) {
      if (v is! Map) continue;
      final name = v['name'];
      final locale = v['locale'];
      if (name is! String || locale is! String || name.isEmpty) continue;
      final tag = locale.toLowerCase().replaceAll('_', '-');
      if (tag != want && !tag.startsWith('$want-')) continue;
      if ('${v['network_required']}' == '1') continue;
      if ('${v['features'] ?? ''}'.split('\t').contains('notInstalled')) {
        continue;
      }
      found.add({'name': name, 'locale': locale});
    }
    if (found.isEmpty) return null;
    final region = preferred[want]?.toLowerCase();
    return found.firstWhere(
      (v) => v['locale']!.toLowerCase().replaceAll('_', '-') == region,
      orElse: () => found.first,
    );
  }

  @override
  Future<bool> prepare(String language) async {
    try {
      final voice = pickVoice(await _tts.getVoices, language);
      if (voice == null || _disposed) return false;
      if (Platform.isIOS) {
        await _tts.setIosAudioCategory(
          IosTextToSpeechAudioCategory.ambient,
          const [],
        );
      }
      if (Platform.isAndroid) await _tts.setQueueMode(0); // flush
      await _tts.awaitSpeakCompletion(false);
      final set = await _tts.setVoice(voice);
      await _tts.setSpeechRate(Platform.isIOS ? 0.5 : 0.6);
      await _tts.setVolume(1);
      return _ready = set == 1 || set == true;
    } on Object catch (e, st) {
      _report(e, st);
      return false;
    }
  }

  @override
  void count(int count) {
    if (!_ready || _disposed || count < 0 || count > 999) return;
    unawaited(_say('$count'));
  }

  Future<void> _say(String text) async {
    try {
      if (Platform.isIOS) await _tts.stop(); // iOS queues by itself
      await _tts.speak(text);
    } on Object catch (e, st) {
      _report(e, st);
    }
  }

  /// A voice that can't speak is not worth more than one report.
  void _report(Object e, StackTrace st) {
    if (_reported) return;
    _reported = true;
    unawaited(Monitoring.captureException(e, st));
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    _ready = false;
    try {
      await _tts.stop();
    } on Object {
      // Nothing to stop.
    }
  }
}
