import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/media/video_info.dart';
import 'package:gym_tracker/core/media/youtube_link.dart';
import 'package:gym_tracker/features/video/presentation/mini_player.dart';
import 'package:gym_tracker/features/video/presentation/video_playback.dart';
import 'package:gym_tracker/features/video/presentation/widgets/video_player_sheet.dart';
import 'package:gym_tracker/features/video/presentation/widgets/youtube_surface.dart';
import 'package:url_launcher/url_launcher.dart';

/// Whose video it is, for analytics (never the id or title).
enum VideoSource { library, gym }

/// Override in tests: `videoInfoRepositoryProvider.overrideWithValue(fake)`.
final videoInfoRepositoryProvider = Provider<VideoInfoRepository>(
  (ref) => OEmbedVideoInfoRepository(),
);

final videoInfoStoreProvider = Provider<VideoInfoStore?>(
  (ref) => Dependencies.videoInfoStore,
);

/// The card's info for a video id: oEmbed, else the phone's copy, else null.
final FutureProviderFamily<VideoInfo?, String> videoInfoProvider =
    FutureProvider.family<VideoInfo?, String>(
      (ref, videoId) => LoadVideoInfo(
        ref.watch(videoInfoRepositoryProvider),
        ref.watch(videoInfoStoreProvider),
      )(YouTubeVideoRef(videoId)),
    );

/// The player. Tests override it with a fake.
final videoSurfaceProvider = Provider<VideoSurfaceBuilder>(
  (ref) => YouTubeSurface.build,
);

/// Opens a video's YouTube page in the YouTube app or the browser. The URL
/// is built from the id only (`YouTubeVideoRef.watchUrl`).
typedef ExternalOpener = Future<bool> Function(Uri url);

final externalOpenerProvider = Provider<ExternalOpener>(
  (ref) =>
      (url) => launchUrl(url, mode: LaunchMode.externalApplication),
);

final videoActionsProvider = Provider<VideoActions>(VideoActions.new);

/// Play (the sheet) and "Open in YouTube", with their analytics events.
class VideoActions {
  new(this._ref);

  final Ref _ref;

  Future<void> play(
    BuildContext context,
    YouTubeVideoRef video,
    VideoSource source, {
    VideoInfo? info,
  }) async {
    unawaited(Analytics.capture('video_played', {'source': source.name}));
    // One player at a time: the sheet takes over from the mini player.
    _ref.read(miniPlayerProvider.notifier).close();
    final playback = VideoPlayback();
    await showVideoPlayerSheet(
      context: context,
      video: video,
      info: info,
      surface: _ref.read(videoSurfaceProvider),
      playback: playback,
      onOpenInYouTube: () => unawaited(openInYouTube(video, source)),
      onMinimize: () {
        unawaited(
          Analytics.capture('video_minimized', {'source': source.name}),
        );
        _ref
            .read(miniPlayerProvider.notifier)
            .show(video, source, at: playback.seconds, info: info);
      },
    );
    playback.dispose();
  }

  Future<void> openInYouTube(YouTubeVideoRef video, VideoSource source) async {
    unawaited(
      Analytics.capture('video_open_in_youtube', {'source': source.name}),
    );
    await _ref.read(externalOpenerProvider)(video.watchUrl);
  }
}
