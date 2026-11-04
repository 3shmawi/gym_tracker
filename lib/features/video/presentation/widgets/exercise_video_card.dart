import 'package:flutter/material.dart';
import 'package:gym_tracker/core/media/video_info.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// What the card knows about the exercise's video.
@immutable
class ExerciseVideoCardData {
  const new({
    required this.thumbnail,
    this.info,
    this.loading = false,
    this.offline = false,
  });

  /// The thumbnail (through the phone's picture cache).
  final ImageProvider thumbnail;

  /// From oEmbed or the phone's copy; null while loading, or offline and
  /// never seen.
  final VideoInfo? info;
  final bool loading;
  final bool offline;
}

/// The how-to video card under the exercise's name (design board 3.1).
/// Never plays by itself: [onPlay] opens the player sheet. Pure UI.
class ExerciseVideoCard extends StatelessWidget {
  const new({
    required this.data,
    required this.onPlay,
    required this.onOpenInYouTube,
    super.key,
  });

  final ExerciseVideoCardData data;
  final VoidCallback onPlay;
  final VoidCallback onOpenInYouTube;

  @override
  Widget build(BuildContext context) {
    final info = data.info;
    final Widget body;
    if (data.loading && info == null) {
      body = const _Loading();
    } else if (info == null) {
      // Offline, never seen: we know a video exists, nothing more (3.1-F).
      body = _NeutralBox(text: context.l10n.videoNeedsInternetUnseen);
    } else {
      switch (info.availability) {
        case VideoAvailability.unavailable:
          return const _Unavailable();
        case VideoAvailability.embedDisabled:
          body = _Blocked(
            data: data,
            message: context.l10n.videoEmbedDisabled,
            onOpenInYouTube: onOpenInYouTube,
          );
        case VideoAvailability.available:
          body = _Ready(data: data, info: info, onPlay: onPlay);
      }
    }
    return AppCard(padding: EdgeInsets.all(AppDimens.scaled(10)), child: body);
  }
}

/// The 16:9 thumbnail box; a Short sits in the middle on a dark fill so the
/// card keeps the same height (3.1-G).
class VideoThumbnail extends StatelessWidget {
  const new({
    required this.image,
    this.vertical = false,
    this.dim = false,
    this.child,
    super.key,
  });

  final ImageProvider image;
  final bool vertical;
  final bool dim;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final picture = Image(
      image: image,
      fit: vertical ? BoxFit.contain : BoxFit.cover,
      errorBuilder: (_, _, _) => ColoredBox(color: palette.fillSubtle),
      frameBuilder: (context, child, frame, sync) =>
          frame != null || sync ? child : ColoredBox(color: palette.fillSubtle),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppDimens.scaled(16)),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ExcludeSemantics(
              child: vertical
                  ? ColoredBox(color: Colors.black, child: picture)
                  : picture,
            ),
            // A scrim keeps white text ≥ 4.5:1 on any thumbnail.
            if (dim) const ColoredBox(color: Color(0x73000000)),
            ?child,
          ],
        ),
      ),
    );
  }
}

class _Ready extends StatelessWidget {
  const new({required this.data, required this.info, required this.onPlay});

  final ExerciseVideoCardData data;
  final VideoInfo info;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final offline = data.offline;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppDimens.sm2,
      children: [
        VideoThumbnail(
          image: data.thumbnail,
          vertical: info.vertical,
          dim: offline,
          child: offline
              ? _Message(
                  icon: Icons.wifi_off_rounded,
                  text: l10n.videoNeedsInternet,
                )
              : Center(
                  child: Semantics(
                    container: true,
                    button: true,
                    label: info.title.isEmpty
                        ? l10n.videoPlayNoTitle
                        : l10n.videoPlay(info.title),
                    excludeSemantics: true,
                    child: _PlayButton(onPressed: onPlay),
                  ),
                ),
        ),
        _Meta(info: info),
      ],
    );
  }
}

class _Blocked extends StatelessWidget {
  const new({
    required this.data,
    required this.message,
    required this.onOpenInYouTube,
  });

  final ExerciseVideoCardData data;
  final String message;
  final VoidCallback onOpenInYouTube;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: AppDimens.sm2,
    children: [
      VideoThumbnail(
        image: data.thumbnail,
        vertical: data.info?.vertical ?? false,
        dim: true,
        child: _Message(icon: Icons.info_outline_rounded, text: message),
      ),
      OpenInYouTubeButton(onPressed: onOpenInYouTube),
    ],
  );
}

/// "Open in YouTube" (an icon and the label; opens the app or browser).
class OpenInYouTubeButton extends StatelessWidget {
  const new({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Semantics(
      button: true,
      label: l10n.videoOpenInYouTubeLabel,
      excludeSemantics: true,
      child: AppSecondaryButton(
        key: const Key('video_open_in_youtube'),
        label: l10n.videoOpenInYouTube,
        icon: Icons.open_in_new_rounded,
        onPressed: onPressed,
      ),
    );
  }
}

class _Unavailable extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    return AppCard(
      child: Row(
        spacing: AppDimens.sm2,
        children: [
          Container(
            width: AppDimens.minTouchTarget,
            height: AppDimens.minTouchTarget,
            decoration: BoxDecoration(
              color: palette.fillSubtle,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.videocam_off_outlined,
              color: palette.textSecondary,
              size: AppDimens.iconMd,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.videoUnavailable,
                  style: AppTextStyles.body.copyWith(
                    color: palette.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  l10n.videoUnavailableDetail,
                  style: AppTextStyles.caption.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NeutralBox extends StatelessWidget {
  const new({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(AppDimens.scaled(16)),
    // 16:9 like a thumbnail, taller when large text needs it.
    child: LayoutBuilder(
      builder: (context, constraints) => ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxWidth * 9 / 16),
        child: ColoredBox(
          color: context.palette.fillSubtle,
          child: Padding(
            padding: EdgeInsetsDirectional.symmetric(vertical: AppDimens.md),
            child: _Message(
              icon: Icons.wifi_off_rounded,
              text: text,
              color: context.palette.textSecondary,
            ),
          ),
        ),
      ),
    ),
  );
}

class _Loading extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final fill = context.palette.fillSubtle;
    Widget bar(double widthFactor, double height) => FractionallySizedBox(
      alignment: AlignmentDirectional.centerStart,
      widthFactor: widthFactor,
      child: Container(
        height: AppDimens.scaled(height),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        ),
      ),
    );
    return Semantics(
      label: context.l10n.loading,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppDimens.sm,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppDimens.scaled(16)),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(color: fill),
            ),
          ),
          bar(0.8, 14),
          bar(0.45, 10),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const new({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return Center(
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(horizontal: AppDimens.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: AppDimens.xs,
          children: [
            Icon(icon, color: c, size: AppDimens.scaled(28)),
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppTextStyles.body.copyWith(
                color: c,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const new({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0x9E000000),
    shape: const CircleBorder(side: BorderSide(color: Color(0x40FFFFFF))),
    child: InkWell(
      key: const Key('video_play'),
      customBorder: const CircleBorder(),
      onTap: onPressed,
      child: SizedBox.square(
        dimension: AppDimens.scaled(64),
        child: Icon(
          Icons.play_arrow_rounded,
          color: Colors.white,
          size: AppDimens.scaled(34),
        ),
      ),
    ),
  );
}

class _Meta extends StatelessWidget {
  const new({required this.info});

  final VideoInfo info;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final source = info.vertical ? l10n.videoYouTubeShorts : l10n.videoYouTube;
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(horizontal: AppDimens.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: AppDimens.scaled(2),
        children: [
          if (info.title.isNotEmpty)
            Text(
              info.title,
              style: AppTextStyles.body.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          Text(
            [if (info.channel.isNotEmpty) info.channel, source].join(' · '),
            style: AppTextStyles.caption.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}
