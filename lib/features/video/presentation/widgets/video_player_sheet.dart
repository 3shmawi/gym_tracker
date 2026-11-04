import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gym_tracker/core/media/video_info.dart';
import 'package:gym_tracker/core/media/youtube_link.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/video/presentation/video_playback.dart';
import 'package:gym_tracker/features/video/presentation/widgets/exercise_video_card.dart';
import 'package:gym_tracker/features/video/presentation/widgets/youtube_surface.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// The player's box: at least 200×200 (YouTube Required Minimum
/// Functionality), full width. A wide video is 16:9 with black bands when
/// that would be under 200 high; a Short is 9:16, centred.
@visibleForTesting
Size videoPlayerSize({
  required double width,
  required double maxHeight,
  required bool vertical,
}) {
  const min = 200.0;
  if (!vertical) return Size(width, math.max(min, width * 9 / 16));
  // A Short: as tall as the room allows, at least 200 wide.
  final height = math.max(min * 16 / 9, math.min(maxHeight, width * 16 / 9));
  return Size(math.max(min, math.min(width, height * 9 / 16)), height);
}

/// The full player sheet (design board 3.2 / 3.3, with the owner's change of
/// 2026-11-03: the player spans the full width and is at least 200 high).
/// Pure UI: [surface] builds the player (the real YouTube player, a fake in
/// tests).
class VideoPlayerSheet extends StatefulWidget {
  const new({
    required this.video,
    required this.surface,
    required this.onClose,
    required this.onOpenInYouTube,
    this.info,
    this.playback,
    this.onMinimize,
    super.key,
  });

  final YouTubeVideoRef video;
  final VideoInfo? info;
  final VideoSurfaceBuilder surface;
  final VoidCallback onClose;
  final VoidCallback onOpenInYouTube;

  /// Where the player is (to carry it to the mini player).
  final VideoPlayback? playback;

  /// "Keep watching while you train": the mini player (V-C); null hides it.
  final VoidCallback? onMinimize;

  @override
  State<VideoPlayerSheet> createState() => _VideoPlayerSheetState();
}

class _VideoPlayerSheetState extends State<VideoPlayerSheet> {
  VideoProblem? _problem;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final info = widget.info;
    final vertical = info?.vertical ?? false;
    final screen = MediaQuery.sizeOf(context);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.symmetric(horizontal: AppDimens.sm),
            child: Row(
              children: [
                const SizedBox(width: AppDimens.minTouchTarget),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.videoSheetTitle,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.title.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                ),
                AppIconButton(
                  key: const Key('video_close'),
                  icon: Icons.close_rounded,
                  tooltip: l10n.videoClose,
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
          SizedBox(height: AppDimens.sm),
          LayoutBuilder(
            builder: (context, constraints) {
              final size = videoPlayerSize(
                width: constraints.maxWidth,
                maxHeight: screen.height * 0.55,
                vertical: vertical,
              );
              return ColoredBox(
                color: Colors.black,
                child: Center(
                  child: SizedBox(
                    key: const Key('video_player_box'),
                    width: size.width,
                    height: size.height,
                    child: _problem == null
                        ? widget.surface(
                            widget.video,
                            onProblem: (p) => setState(() => _problem = p),
                            playback: widget.playback,
                          )
                        : _ProblemView(problem: _problem!),
                  ),
                ),
              );
            },
          ),
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              AppDimens.md,
              AppDimens.sm2,
              AppDimens.md,
              AppDimens.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppDimens.sm2,
              children: [
                if (info != null && info.title.isNotEmpty)
                  Text(
                    info.title,
                    style: AppTextStyles.title.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                if (info != null)
                  Text(
                    [
                      if (info.channel.isNotEmpty) info.channel,
                      if (info.vertical)
                        l10n.videoYouTubeShorts
                      else
                        l10n.videoYouTube,
                    ].join(' · '),
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                if (widget.onMinimize case final minimize?
                    when _problem == null)
                  AppSecondaryButton(
                    key: const Key('video_minimize'),
                    icon: Icons.picture_in_picture_alt_rounded,
                    label: l10n.videoMinimize,
                    onPressed: minimize,
                  ),
                OpenInYouTubeButton(onPressed: widget.onOpenInYouTube),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProblemView extends StatelessWidget {
  const new({required this.problem});

  final VideoProblem problem;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (icon, text) = switch (problem) {
      VideoProblem.onlyOnYouTube => (
        Icons.info_outline_rounded,
        l10n.videoOnlyOnYouTube,
      ),
      VideoProblem.unavailable => (
        Icons.videocam_off_outlined,
        l10n.videoUnavailable,
      ),
      VideoProblem.failed => (
        Icons.error_outline_rounded,
        l10n.videoOnlyOnYouTube,
      ),
    };
    return Center(
      key: const Key('video_problem'),
      child: Padding(
        padding: EdgeInsetsDirectional.all(AppDimens.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: AppDimens.sm,
          children: [
            Icon(icon, color: Colors.white, size: AppDimens.scaled(32)),
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the sheet over the current screen.
Future<void> showVideoPlayerSheet({
  required BuildContext context,
  required YouTubeVideoRef video,
  required VideoInfo? info,
  required VideoSurfaceBuilder surface,
  required VoidCallback onOpenInYouTube,
  VideoPlayback? playback,
  VoidCallback? onMinimize,
}) => showAppSheet<void>(
  context: context,
  builder: (sheet) => VideoPlayerSheet(
    video: video,
    info: info,
    surface: surface,
    playback: playback,
    onClose: () => Navigator.of(sheet).pop(),
    onOpenInYouTube: onOpenInYouTube,
    onMinimize: onMinimize == null
        ? null
        : () {
            onMinimize();
            Navigator.of(sheet).pop();
          },
  ),
);
