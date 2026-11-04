import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gym_tracker/core/media/youtube_link.dart';
import 'package:gym_tracker/core/router/link_guard.dart';
import 'package:gym_tracker/features/video/presentation/video_playback.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// What can go wrong while playing, as the sheet shows it.
enum VideoProblem {
  /// The owner blocks embedding, or YouTube wants it watched there
  /// (errors 101, 150, 152; age-restricted videos land here too).
  onlyOnYouTube,

  /// Removed or private (errors 100, 105).
  unavailable,

  /// Anything else (including 153, a missing Referer).
  failed,
}

/// Builds the player for [video]; tests pass a fake (a WebView does not run
/// in widget tests).
typedef VideoSurfaceBuilder = Widget Function(
  YouTubeVideoRef video, {
  required ValueChanged<VideoProblem> onProblem,
  VideoPlayback? playback,
});

/// YouTube's official embedded player (youtube_player_iframe), in the
/// privacy-enhanced mode (`youtube-nocookie.com`), with the app identified
/// through the Referer as YouTube's Required Minimum Functionality asks: the
/// player page is loaded with `baseUrl` = [origin]. Plays once the sheet is
/// visible (the trainee tapped play); YouTube's own controls and branding are
/// untouched and nothing is drawn over the player.
class YouTubeSurface extends StatefulWidget {
  const new({
    required this.video,
    required this.onProblem,
    this.playback,
    super.key,
  });

  /// The app's identity for YouTube (`https://<application id>`).
  static const origin = 'https://com.mohager.azm';

  final YouTubeVideoRef video;
  final ValueChanged<VideoProblem> onProblem;
  final VideoPlayback? playback;

  static Widget build(
    YouTubeVideoRef video, {
    required ValueChanged<VideoProblem> onProblem,
    VideoPlayback? playback,
  }) => YouTubeSurface(video: video, onProblem: onProblem, playback: playback);

  @override
  State<YouTubeSurface> createState() => _YouTubeSurfaceState();
}

/// Pauses as soon as the app leaves the screen: YouTube's Developer Policies
/// forbid playing "from a background player, meaning a player that is not
/// displayed in the page, tab, or screen that the user is viewing"
/// (docs/decisions/video_outside_app.md).
class _YouTubeSurfaceState extends State<YouTubeSurface>
    with WidgetsBindingObserver, IgnoresLinks {
  late final YoutubePlayerController _controller;
  StreamSubscription<YoutubePlayerValue>? _values;
  StreamSubscription<YoutubeVideoState>? _position;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final v = widget.video;
    _controller = YoutubePlayerController.fromVideoId(
      videoId: v.id,
      autoPlay: true,
      startSeconds: v.start?.toDouble(),
      endSeconds: v.end?.toDouble(),
      params: const YoutubePlayerParams(
        origin: YouTubeSurface.origin,
        strictRelatedVideos: true,
        showFullscreenButton: true,
      ),
    );
    _values = _controller.stream.listen((value) {
      final problem = switch (value.error) {
        YoutubeError.none => null,
        YoutubeError.notEmbeddable ||
        YoutubeError.sameAsNotEmbeddable ||
        YoutubeError.sameAsNotEmbeddable2 => VideoProblem.onlyOnYouTube,
        YoutubeError.videoNotFound ||
        YoutubeError.cannotFindVideo => VideoProblem.unavailable,
        _ => VideoProblem.failed,
      };
      if (problem != null && mounted) widget.onProblem(problem);
      widget.playback?.report(paused: value.playerState == PlayerState.paused);
    });
    final playback = widget.playback;
    if (playback != null) {
      playback.attach(
        pause: () => unawaited(_controller.pauseVideo()),
        play: () => unawaited(_controller.playVideo()),
      );
      _position = _controller.videoStateStream.listen(
        (s) => playback.report(seconds: s.position.inSeconds),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_controller.pauseVideo());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_controller.pauseVideo());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_values?.cancel());
    unawaited(_position?.cancel());
    widget.playback?.detach();
    unawaited(_controller.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      YoutubePlayer(controller: _controller, backgroundColor: Colors.black);
}
