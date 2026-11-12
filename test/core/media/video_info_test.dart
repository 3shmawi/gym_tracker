import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/media/video_info.dart';
import 'package:gym_tracker/core/media/youtube_link.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/library/data/exercise_catalog.dart';
import 'package:gym_tracker/features/library/data/exercise_videos.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const video = YouTubeVideoRef('mCEIUZySRPY');

OEmbedVideoInfoRepository repo(http.Response Function(http.Request) answer) =>
    OEmbedVideoInfoRepository(
      client: MockClient((r) async => answer(r)),
      retries: 0,
    );

http.Response json(Map<String, Object> body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status);

void main() {
  group(OEmbedVideoInfoRepository, () {
    test('asks oEmbed with the Shorts form of the link, no key', () async {
      Uri? asked;
      await repo((r) {
        asked = r.url;
        return json({
          'title': 't',
          'author_name': 'c',
          'width': 200,
          'height': 113,
        });
      }).fetch(video);
      expect(
        asked.toString(),
        'https://www.youtube.com/oembed?format=json&url=https%3A%2F%2Fwww.youtube.com%2Fshorts%2FmCEIUZySRPY',
      );
    });

    test('a normal video and a Short', () async {
      final wide = await repo(
        (_) => json({
          'title': 'Bench',
          'author_name': 'Coach',
          'width': 200,
          'height': 113,
        }),
      ).fetch(video);
      final info = (wide as Success<VideoInfo>).value;
      expect(info.availability, VideoAvailability.available);
      expect(info.title, 'Bench');
      expect(info.channel, 'Coach');
      expect(info.vertical, isFalse);
      final tall = await repo(
        (_) => json({
          'title': 'S',
          'author_name': 'C',
          'width': 113,
          'height': 200,
        }),
      ).fetch(video);
      expect((tall as Success<VideoInfo>).value.vertical, isTrue);
    });

    test('embedding off (401) and removed (404, 400)', () async {
      for (final (status, want) in [
        (401, VideoAvailability.embedDisabled),
        (403, VideoAvailability.embedDisabled),
        (404, VideoAvailability.unavailable),
        (400, VideoAvailability.unavailable),
      ]) {
        final r = await repo((_) => http.Response('', status)).fetch(video);
        expect(
          (r as Success<VideoInfo>).value.availability,
          want,
          reason: '$status',
        );
      }
    });

    test('a server error or offline is a failure, never a throw', () async {
      expect(
        await repo((_) => http.Response('', 500)).fetch(video),
        isA<Failed<VideoInfo>>(),
      );
      final offline = OEmbedVideoInfoRepository(
        client: MockClient((_) async => throw http.ClientException('offline')),
        retries: 0,
      );
      expect(await offline.fetch(video), isA<Failed<VideoInfo>>());
    });

    test('hostile text from YouTube is cleaned and capped', () async {
      final r = await repo(
        (_) => json({
          'title': 'A\u202Eevil\u0000\n${'x' * 500}',
          'author_name': 42,
          'width': 'a',
          'height': 'b',
        }),
      ).fetch(video);
      final info = (r as Success<VideoInfo>).value;
      expect(info.title, isNot(contains('\u202E')));
      expect(info.title, isNot(contains('\u0000')));
      expect(info.title.runes.length, lessThanOrEqualTo(VideoInfo.maxText));
      expect(info.channel, '');
      expect(info.vertical, isFalse);
    });

    test('a malformed id never reaches the network', () async {
      var asked = false;
      final r = await repo((_) {
        asked = true;
        return json({});
      }).fetch(const YouTubeVideoRef('../x'));
      expect(asked, isFalse);
      expect(
        (r as Success<VideoInfo>).value.availability,
        VideoAvailability.unavailable,
      );
    });

    test('the thumbnail is built from the id only', () {
      expect(
        VideoInfo.thumbnail('mCEIUZySRPY').toString(),
        'https://i.ytimg.com/vi/mCEIUZySRPY/hqdefault.jpg',
      );
    });
  });

  group('LoadVideoInfo and the offline copy', () {
    test(
      'online: fresh and kept; offline: the copy; never seen: null',
      () async {
        SharedPreferences.setMockInitialValues({});
        final store = VideoInfoStore(await SharedPreferences.getInstance());
        final online = LoadVideoInfo(
          repo(
            (_) => json({
              'title': 'T',
              'author_name': 'C',
              'width': 2,
              'height': 1,
            }),
          ),
          store,
        );
        expect((await online(video))!.title, 'T');
        await Future<void>.delayed(Duration.zero);
        final offline = LoadVideoInfo(
          repo((_) => throw http.ClientException('offline')),
          store,
        );
        expect((await offline(video))!.title, 'T');
        expect(await offline(const YouTubeVideoRef('aaaaaaaaaaa')), isNull);
      },
    );

    test('a broken copy is ignored', () async {
      SharedPreferences.setMockInitialValues({
        VideoInfoStore.key(video.id): '{not json',
      });
      final store = VideoInfoStore(await SharedPreferences.getInstance());
      expect(store.load(video.id), isNull);
    });
  });

  group(ExerciseVideos, () {
    test('every approved video is a valid id of a library exercise', () {
      final ids = {for (final e in ExerciseCatalog.all) e.id};
      // Videos are approved by the owner; the 13 exercises added on
      // 2026-11-10 (days 4 and 5) have none yet and show pictures and steps.
      expect(ExerciseVideos.exerciseIds, hasLength(23));
      for (final id in ExerciseVideos.exerciseIds) {
        expect(ids, contains(id));
        final v = ExerciseVideos.of(id)!;
        expect(
          YouTubeVideoRef.isValid(v.id, start: v.start, end: v.end),
          isTrue,
        );
      }
    });
  });
}
