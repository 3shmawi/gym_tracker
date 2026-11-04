import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/media/youtube_link.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/video/presentation/mini_player.dart';
import 'package:gym_tracker/features/video/presentation/video_playback.dart';
import 'package:gym_tracker/features/video/presentation/video_providers.dart';
import 'package:gym_tracker/features/video/presentation/widgets/mini_player_view.dart';
import 'package:gym_tracker/features/video/presentation/widgets/youtube_surface.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/ui_check.dart';

const video = YouTubeVideoRef('mCEIUZySRPY');

Widget fakeSurface(
  YouTubeVideoRef v, {
  required ValueChanged<VideoProblem> onProblem,
  VideoPlayback? playback,
}) => const ColoredBox(key: Key('fake_player'), color: Colors.black);

class Calls {
  int expands = 0;
  int closes = 0;
  int pauses = 0;
  int plays = 0;
}

Widget mini({VideoPlayback? playback, Calls? calls, String title = 'Bench'}) {
  final c = calls ?? Calls();
  final p = (playback ?? VideoPlayback())
    ..attach(pause: () => c.pauses++, play: () => c.plays++);
  return AppScaffold(
    body: Align(
      alignment: AlignmentDirectional.topEnd,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: MiniPlayerView(
          video: video,
          title: title,
          surface: fakeSurface,
          playback: p,
          onExpand: () => c.expands++,
          onClose: () => c.closes++,
        ),
      ),
    ),
  );
}

void main() {
  group('nearestCorner', () {
    test('left-to-right', () {
      MiniCorner at(double x, double y) =>
          nearestCorner(x: x, y: y, width: 400, height: 800, rtl: false);
      expect(at(50, 50), MiniCorner.topStart);
      expect(at(350, 50), MiniCorner.topEnd);
      expect(at(50, 700), MiniCorner.bottomStart);
      expect(at(350, 700), MiniCorner.bottomEnd);
    });

    test('right-to-left swaps start and end', () {
      expect(
        nearestCorner(x: 50, y: 50, width: 400, height: 800, rtl: true),
        MiniCorner.topEnd,
      );
    });
  });

  group('atSecond', () {
    test('continues where the sheet was, inside the clip', () {
      const clip = YouTubeVideoRef('mCEIUZySRPY', start: 10, end: 60);
      expect(atSecond(clip, 42).start, 42);
      expect(atSecond(clip, 0).start, 10, reason: 'not started: its start');
      expect(atSecond(clip, 61).start, 10, reason: 'past the end');
      expect(atSecond(clip, 42).end, 60);
    });
  });

  test('the controller shows, moves and closes', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final ctl = c.read(miniPlayerProvider.notifier)
      ..show(video, VideoSource.library, at: 30);
    expect(c.read(miniPlayerProvider)!.video.start, 30);
    expect(c.read(miniPlayerProvider)!.corner, MiniCorner.topEnd);
    ctl.moveTo(MiniCorner.bottomStart);
    expect(c.read(miniPlayerProvider)!.corner, MiniCorner.bottomStart);
    ctl.show(video, VideoSource.gym, at: 5);
    expect(
      c.read(miniPlayerProvider)!.corner,
      MiniCorner.bottomStart,
      reason: 'a new video keeps the corner the member chose',
    );
    ctl.close();
    expect(c.read(miniPlayerProvider), isNull);
  });

  group(MiniPlayerView, () {
    testWidgets('YouTube minimum: the player box is 200×200', (tester) async {
      await tester.pumpApp(mini());
      expect(
        tester.getSize(find.byKey(const Key('mini_player_box'))),
        const Size(200, 200),
      );
      expect(find.bySemanticsLabel('Mini video player: Bench'), findsOneWidget);
    });

    testWidgets('pause / play follow the player; expand; close', (
      tester,
    ) async {
      final calls = Calls();
      final playback = VideoPlayback();
      await tester.pumpApp(mini(playback: playback, calls: calls));
      await tester.tap(find.byTooltip('Pause the video'));
      expect(calls.pauses, 1);
      playback.report(paused: true);
      await tester.pump();
      await tester.tap(find.byTooltip('Play the video'));
      expect(calls.plays, 1);
      await tester.tap(find.byKey(const Key('mini_expand')));
      await tester.tap(find.byKey(const Key('mini_close')));
      expect((calls.expands, calls.closes), (1, 1));
    });

    testWidgets('nothing is drawn over the player', (tester) async {
      await tester.pumpApp(mini());
      final player = tester.getRect(find.byKey(const Key('fake_player')));
      for (final key in ['mini_pause', 'mini_expand', 'mini_close']) {
        expect(
          tester.getRect(find.byKey(Key(key))).overlaps(player),
          isFalse,
          reason: key,
        );
      }
    });
  });

  screensUiTests({
    'mini_player': mini,
    'mini_player_paused': () =>
        mini(playback: VideoPlayback()..report(paused: true), title: ''),
  });
}
