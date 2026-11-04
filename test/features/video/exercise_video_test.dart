import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/media/video_info.dart';
import 'package:gym_tracker/core/media/youtube_link.dart';
import 'package:gym_tracker/features/video/presentation/widgets/exercise_video_card.dart';
import 'package:gym_tracker/features/video/presentation/widgets/video_player_sheet.dart';
import 'package:gym_tracker/features/video/presentation/widgets/youtube_surface.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/ui_check.dart';

/// A bundled drawing stands in for the YouTube thumbnail in tests.
const thumb = AssetImage('assets/exercises/flat_db_press.webp');
const video = YouTubeVideoRef('mCEIUZySRPY');

const wide = VideoInfo(
  availability: VideoAvailability.available,
  title: 'طريقة أداء تمرين الصدر المستوي بالدامبل',
  channel: 'Coach',
);
const short = VideoInfo(
  availability: VideoAvailability.available,
  title: 'Machine Incline Press',
  channel: 'Coach',
  vertical: true,
);

class Calls {
  int plays = 0;
  int opens = 0;
  int closes = 0;
}

Widget card(
  VideoInfo? info, {
  bool loading = false,
  bool offline = false,
  Calls? calls,
}) {
  final c = calls ?? Calls();
  return Scaffold(
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ExerciseVideoCard(
          data: ExerciseVideoCardData(
            thumbnail: thumb,
            info: info,
            loading: loading,
            offline: offline,
          ),
          onPlay: () => c.plays++,
          onOpenInYouTube: () => c.opens++,
        ),
      ],
    ),
  );
}

/// A stand-in for the YouTube player (a WebView does not run in tests).
Widget fakeSurface(
  YouTubeVideoRef v, {
  required ValueChanged<VideoProblem> onProblem,
}) => ColoredBox(
  key: const Key('fake_player'),
  color: Colors.black,
  child: Center(
    child: TextButton(
      key: const Key('fake_player_error'),
      style: TextButton.styleFrom(foregroundColor: Colors.white),
      onPressed: () => onProblem(VideoProblem.onlyOnYouTube),
      child: Text(v.id),
    ),
  ),
);

Widget sheet(VideoInfo? info, {Calls? calls, VideoSurfaceBuilder? surface}) {
  final c = calls ?? Calls();
  return Scaffold(
    body: SingleChildScrollView(
      child: VideoPlayerSheet(
        video: video,
        info: info,
        surface: surface ?? fakeSurface,
        onClose: () => c.closes++,
        onOpenInYouTube: () => c.opens++,
      ),
    ),
  );
}

void main() {
  group('videoPlayerSize (YouTube: at least 200×200)', () {
    test('a wide video: full width, 16:9, never under 200 high', () {
      expect(
        videoPlayerSize(width: 375, maxHeight: 500, vertical: false),
        const Size(375, 375 * 9 / 16),
      );
      expect(
        videoPlayerSize(width: 320, maxHeight: 500, vertical: false),
        const Size(320, 200),
      );
    });

    test('a Short: 9:16, at least 200 wide and 200 high', () {
      final s = videoPlayerSize(width: 375, maxHeight: 446, vertical: true);
      expect(s.height, 446);
      expect(s.width, closeTo(446 * 9 / 16, 0.01));
      final tight = videoPlayerSize(width: 320, maxHeight: 250, vertical: true);
      expect(tight.width, greaterThanOrEqualTo(200));
      expect(tight.height, greaterThanOrEqualTo(200));
    });
  });

  group(ExerciseVideoCard, () {
    testWidgets('ready: title, channel, play opens the player', (tester) async {
      final handle = tester.ensureSemantics();
      final calls = Calls();
      await tester.pumpApp(card(wide, calls: calls));
      expect(find.text(wide.title), findsOneWidget);
      expect(find.text('Coach · YouTube'), findsOneWidget);
      await tester.tap(find.byKey(const Key('video_play')));
      expect(calls.plays, 1);
      expect(find.bySemanticsLabel('Play video: ${wide.title}'), findsOne);
      handle.dispose();
    });

    testWidgets('never plays by itself', (tester) async {
      await tester.pumpApp(card(wide));
      await tester.pump(const Duration(seconds: 10));
      expect(find.byKey(const Key('fake_player')), findsNothing);
    });

    testWidgets('embedding off: Open in YouTube', (tester) async {
      final calls = Calls();
      await tester.pumpApp(
        card(
          const VideoInfo(availability: VideoAvailability.embedDisabled),
          calls: calls,
        ),
      );
      expect(
        find.text("The video's owner doesn't allow it to play here"),
        findsOneWidget,
      );
      expect(find.byKey(const Key('video_play')), findsNothing);
      await tester.tap(find.byKey(const Key('video_open_in_youtube')));
      expect(calls.opens, 1);
    });

    testWidgets('removed or private: compact, no button', (tester) async {
      await tester.pumpApp(
        card(const VideoInfo(availability: VideoAvailability.unavailable)),
      );
      expect(find.text('Video unavailable'), findsOneWidget);
      expect(find.byKey(const Key('video_open_in_youtube')), findsNothing);
    });

    testWidgets('offline with the copy: thumbnail + Needs internet', (
      tester,
    ) async {
      await tester.pumpApp(card(wide, offline: true));
      expect(find.text('Needs internet'), findsOneWidget);
      expect(find.byKey(const Key('video_play')), findsNothing);
      expect(find.text(wide.title), findsOneWidget);
    });

    testWidgets('offline, never seen: a neutral box', (tester) async {
      await tester.pumpApp(card(null, offline: true));
      expect(
        find.text("There's a video for this exercise. Needs internet"),
        findsOneWidget,
      );
    });

    testWidgets('a Short says so', (tester) async {
      await tester.pumpApp(card(short));
      expect(find.text('Coach · YouTube Shorts'), findsOneWidget);
    });
  });

  group(VideoPlayerSheet, () {
    testWidgets('the player, full width and at least 200 high', (tester) async {
      await tester.pumpApp(sheet(wide));
      expect(find.byKey(const Key('fake_player')), findsOneWidget);
      final box = tester.getSize(find.byKey(const Key('video_player_box')));
      expect(box.width, 375);
      expect(box.height, greaterThanOrEqualTo(200));
    });

    testWidgets('a player error: the message replaces the player', (
      tester,
    ) async {
      await tester.pumpApp(sheet(wide));
      await tester.tap(find.byKey(const Key('fake_player_error')));
      await tester.pump();
      expect(find.byKey(const Key('fake_player')), findsNothing);
      expect(
        find.text('This video can only be watched on YouTube'),
        findsOneWidget,
      );
    });

    testWidgets('close and Open in YouTube', (tester) async {
      final calls = Calls();
      await tester.pumpApp(sheet(wide, calls: calls));
      await tester.tap(find.byKey(const Key('video_close')));
      await tester.tap(find.byKey(const Key('video_open_in_youtube')));
      expect(calls.closes, 1);
      expect(calls.opens, 1);
    });

    testWidgets('nothing is drawn over the player', (tester) async {
      await tester.pumpApp(sheet(wide));
      final player = tester.getRect(find.byKey(const Key('video_player_box')));
      for (final key in ['video_close', 'video_open_in_youtube']) {
        expect(
          tester.getRect(find.byKey(Key(key))).overlaps(player),
          isFalse,
          reason: key,
        );
      }
    });
  });

  screensUiTests({
    'video_card_ready': () => card(wide),
    'video_card_loading': () => card(null, loading: true),
    'video_card_embed_off': () =>
        card(const VideoInfo(availability: VideoAvailability.embedDisabled)),
    'video_card_unavailable': () =>
        card(const VideoInfo(availability: VideoAvailability.unavailable)),
    'video_card_offline_cached': () => card(wide, offline: true),
    'video_card_offline_unseen': () => card(null, offline: true),
    'video_card_short': () => card(short),
    'video_sheet': () => sheet(wide),
    'video_sheet_short': () => sheet(short),
    'video_sheet_problem': () => sheet(
      wide,
      surface: (v, {required onProblem}) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => onProblem(VideoProblem.onlyOnYouTube),
        );
        return const SizedBox.expand();
      },
    ),
  });
}
