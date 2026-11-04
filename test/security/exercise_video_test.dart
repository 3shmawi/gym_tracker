import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/media/media_cache.dart';
import 'package:gym_tracker/core/media/video_info.dart';
import 'package:gym_tracker/core/media/youtube_link.dart';
import 'package:gym_tracker/features/library/data/exercise_videos.dart';

/// How-to videos: only an 11-character id is ever stored or used; every URL
/// the app opens or loads is built from it (docs/features/exercise_videos.md).
void main() {
  final files = [
    for (final dir in ['lib/features/video', 'lib/core/media'])
      for (final f in Directory(dir).listSync(recursive: true))
        if (f is File && f.path.endsWith('.dart')) f,
  ];

  test('the video code builds URLs only from fixed parts and the id', () {
    for (final file in files) {
      final text = file.readAsStringSync();
      expect(
        text,
        isNot(contains('Uri.parse(url')),
        reason: '${file.path}: a URL from a string',
      );
      for (final banned in ['Env.', 'print(', 'debugPrint', 'dart:io']) {
        expect(text, isNot(contains(banned)), reason: '${file.path}: $banned');
      }
    }
  });

  test('"Open in YouTube" opens only the YouTube page of a valid id', () {
    for (final id in ExerciseVideos.exerciseIds) {
      final url = ExerciseVideos.of(id)!.watchUrl;
      expect(url.scheme, 'https');
      expect(url.host, 'www.youtube.com');
      expect(url.path, '/watch');
      expect(
        YouTubeVideoRef.idPattern.hasMatch(url.queryParameters['v']!),
        isTrue,
      );
    }
  });

  test('thumbnails come from i.ytimg.com only, and the cache allows it', () {
    final url = VideoInfo.thumbnail('mCEIUZySRPY');
    expect(url.host, 'i.ytimg.com');
    expect(MediaCache.isAllowed(url), isTrue);
    expect(
      MediaCache.isAllowed(Uri.parse('https://i.ytimg.com.evil.example/x.jpg')),
      isFalse,
    );
  });

  test('the player runs in privacy-enhanced mode with the app as origin', () {
    final surface = File(
      'lib/features/video/presentation/widgets/youtube_surface.dart',
    ).readAsStringSync();
    expect(surface, contains("origin = 'https://com.mohager.azm'"));
    // privacyEnhancedMode defaults to true in youtube_player_iframe 6.0.2;
    // nothing may turn it off.
    expect(surface, isNot(contains('privacyEnhancedMode: false')));
    expect(surface, isNot(contains('autoplay')));
  });

  test('no background play: the player pauses when the app leaves the '
      'screen, and nothing enables background audio or PiP', () {
    final surface = File(
      'lib/features/video/presentation/widgets/youtube_surface.dart',
    ).readAsStringSync();
    expect(surface, contains('didChangeAppLifecycleState'));
    expect(surface, contains('AppLifecycleState.resumed'));
    expect(surface, contains('pauseVideo()'));
    final plist = File('ios/Runner/Info.plist').readAsStringSync();
    expect(plist, isNot(contains('UIBackgroundModes')));
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(manifest, isNot(contains('supportsPictureInPicture="true"')));
    expect(manifest, isNot(contains('FOREGROUND_SERVICE_MEDIA_PLAYBACK')));
  });
}
