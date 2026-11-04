import 'package:flutter/material.dart';
import 'package:gym_tracker/core/media/youtube_link.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/video/presentation/video_playback.dart';
import 'package:gym_tracker/features/video/presentation/widgets/youtube_surface.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// The floating mini player (board 4.1–4.2, grown to YouTube's 200×200
/// minimum): YouTube's own player, untouched, and under it pause/play,
/// expand and close (48×48 each). Pure UI.
class MiniPlayerView extends StatelessWidget {
  const new({
    required this.video,
    required this.title,
    required this.surface,
    required this.playback,
    required this.onExpand,
    required this.onClose,
    super.key,
  });

  /// YouTube's minimum player size (Required Minimum Functionality).
  static const playerSide = 200.0;

  final YouTubeVideoRef video;

  /// The video's title for screen readers; empty when unknown.
  final String title;
  final VideoSurfaceBuilder surface;
  final VideoPlayback playback;
  final VoidCallback onExpand;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      container: true,
      label: title.isEmpty
          ? l10n.miniPlayerLabelNoTitle
          : l10n.miniPlayerLabel(title),
      child: SizedBox(
        width: playerSide + 2 * AppDimens.scaled(6),
        child: AppCard(
          padding: EdgeInsets.all(AppDimens.scaled(6)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: AppDimens.scaled(6),
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppDimens.scaled(12)),
                child: ColoredBox(
                  color: Colors.black,
                  child: SizedBox.square(
                    key: const Key('mini_player_box'),
                    dimension: playerSide,
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: surface(
                          video,
                          onProblem: (_) {},
                          playback: playback,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: playback,
                builder: (context, _) => Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    AppIconButton(
                      key: const Key('mini_pause'),
                      icon: playback.paused
                          ? Icons.play_arrow_rounded
                          : Icons.pause_rounded,
                      tooltip: playback.paused
                          ? l10n.videoResume
                          : l10n.videoPause,
                      onPressed: playback.paused
                          ? playback.play
                          : playback.pause,
                    ),
                    AppIconButton(
                      key: const Key('mini_expand'),
                      icon: Icons.open_in_full_rounded,
                      tooltip: l10n.videoExpand,
                      onPressed: onExpand,
                    ),
                    AppIconButton(
                      key: const Key('mini_close'),
                      icon: Icons.close_rounded,
                      tooltip: l10n.videoClose,
                      onPressed: onClose,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
