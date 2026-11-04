import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/media/video_info.dart';
import 'package:gym_tracker/core/media/youtube_link.dart';
import 'package:gym_tracker/features/video/presentation/video_providers.dart';

/// A corner the mini player snaps to (board 4.3). `start`/`end` follow the
/// reading direction.
enum MiniCorner { topStart, topEnd, bottomStart, bottomEnd }

/// The video in the floating mini player (stage V-C), or none.
@immutable
class MiniPlayerState {
  const new({
    required this.video,
    required this.source,
    this.info,
    this.corner = MiniCorner.topEnd,
  });

  /// Starts where the sheet left it (`start` = the second it was at).
  final YouTubeVideoRef video;
  final VideoSource source;
  final VideoInfo? info;
  final MiniCorner corner;

  MiniPlayerState copyWith({MiniCorner? corner}) => MiniPlayerState(
    video: video,
    source: source,
    info: info,
    corner: corner ?? this.corner,
  );
}

final miniPlayerProvider =
    NotifierProvider<MiniPlayerController, MiniPlayerState?>(
      MiniPlayerController.new,
    );

class MiniPlayerController extends Notifier<MiniPlayerState?> {
  @override
  MiniPlayerState? build() => null;

  /// Shows [video] in the mini player from second [at] (the sheet's place).
  void show(
    YouTubeVideoRef video,
    VideoSource source, {
    required int at,
    VideoInfo? info,
  }) {
    state = MiniPlayerState(
      video: atSecond(video, at),
      source: source,
      info: info,
      corner: state?.corner ?? MiniCorner.topEnd,
    );
  }

  void moveTo(MiniCorner corner) {
    final s = state;
    if (s != null) state = s.copyWith(corner: corner);
  }

  void close() => state = null;
}

/// [video] from second [at] (kept inside its end); its own start otherwise.
YouTubeVideoRef atSecond(YouTubeVideoRef video, int at) {
  final end = video.end;
  final start = at > 0 && (end == null || at < end) ? at : video.start;
  return YouTubeVideoRef(video.id, start: start, end: end);
}

/// The height the mini player must stay above at the bottom: the active
/// workout's dock (steppers + Log, or the rest timer), measured at run time
/// (board 4.3). 0 when no dock is on screen.
final miniPlayerBottomReserveProvider =
    NotifierProvider<MiniPlayerReserveController, double>(
      MiniPlayerReserveController.new,
    );

class MiniPlayerReserveController extends Notifier<double> {
  @override
  double build() => 0;

  void set(double value) {
    // May come a microtask after the app (or a test) closed.
    if (!ref.mounted) return;
    if (value != state) state = value;
  }
}

/// Reports the dock's height to [miniPlayerBottomReserveProvider].
extension MiniPlayerReserve on WidgetRef {
  void reserveBottom(double height) =>
      read(miniPlayerBottomReserveProvider.notifier).set(height);
}

/// The corner nearest to [x], [y] (the mini player's centre after a drag) in
/// a [width] × [height] area; [rtl] swaps start and end.
MiniCorner nearestCorner({
  required double x,
  required double y,
  required double width,
  required double height,
  required bool rtl,
}) {
  final left = x < width / 2;
  final top = y < height / 2;
  final start = rtl ? !left : left;
  return switch ((top, start)) {
    (true, true) => MiniCorner.topStart,
    (true, false) => MiniCorner.topEnd,
    (false, true) => MiniCorner.bottomStart,
    (false, false) => MiniCorner.bottomEnd,
  };
}
