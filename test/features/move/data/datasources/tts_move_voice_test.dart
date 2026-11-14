import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/move/data/datasources/tts_move_voice.dart';

void main() {
  Map<String, String> v(
    String name,
    String locale, {
    String network = '0',
    String features = '',
  }) => {
    'name': name,
    'locale': locale,
    'network_required': network,
    'features': features,
  };

  group('pickVoice', () {
    test('an Egyptian Arabic voice first, any Arabic voice else', () {
      final voices = [
        v('ar-xa-x-arz-local', 'ar-SA'),
        v('ar-eg-x-local', 'ar-EG'),
        v('en-us-x-local', 'en-US'),
      ];
      expect(
        FlutterTtsMoveVoice.pickVoice(voices, 'ar')?['name'],
        'ar-eg-x-local',
      );
      expect(
        FlutterTtsMoveVoice.pickVoice([
          voices.first,
          voices.last,
        ], 'ar')?['name'],
        'ar-xa-x-arz-local',
      );
      expect(FlutterTtsMoveVoice.pickVoice(voices, 'en')?['locale'], 'en-US');
    });

    test('never a voice that needs the internet or is not installed', () {
      final voices = [
        v('ar-eg-x-network', 'ar-EG', network: '1'),
        v(
          'ar-eg-x-missing',
          'ar-EG',
          features: 'networkTimeoutMs\tnotInstalled',
        ),
      ];
      expect(FlutterTtsMoveVoice.pickVoice(voices, 'ar'), isNull);
      expect(
        FlutterTtsMoveVoice.pickVoice([
          ...voices,
          v('ar-x-local', 'ar', features: 'networkTimeoutMs'),
        ], 'ar')?['name'],
        'ar-x-local',
      );
    });

    test('no voice for the language: none (the round plays tones)', () {
      expect(
        FlutterTtsMoveVoice.pickVoice([v('en-us', 'en-US')], 'ar'),
        isNull,
      );
      // "arn" (Mapudungun) is not Arabic.
      expect(FlutterTtsMoveVoice.pickVoice([v('x', 'arn-CL')], 'ar'), isNull);
    });

    test('iOS-style voices (no network field) and underscores work', () {
      final ios = [
        {'name': 'Maged', 'locale': 'ar-SA', 'quality': 'default'},
        {'name': 'Samantha', 'locale': 'en_US'},
      ];
      expect(FlutterTtsMoveVoice.pickVoice(ios, 'ar')?['name'], 'Maged');
      expect(FlutterTtsMoveVoice.pickVoice(ios, 'en')?['name'], 'Samantha');
    });

    test('garbage from the platform never throws', () {
      for (final odd in <Object?>[
        null,
        'voices',
        42,
        [null, 1, 'x', <String, Object?>{}],
        [
          {'name': 7, 'locale': 'ar-EG'},
          {'name': '', 'locale': 'ar-EG'},
          {'name': 'x', 'locale': null},
        ],
      ]) {
        expect(
          FlutterTtsMoveVoice.pickVoice(odd, 'ar'),
          isNull,
          reason: '$odd',
        );
      }
    });
  });
}
