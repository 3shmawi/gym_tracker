import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/features/video/presentation/mini_player.dart';
import 'package:gym_tracker/features/video/presentation/video_playback.dart';
import 'package:gym_tracker/features/video/presentation/video_providers.dart';
import 'package:gym_tracker/features/video/presentation/widgets/mini_player_view.dart';

/// Floats the mini player over every screen (above the router, under the
/// app's sheets' barrier). It keeps clear of the status bar and app bar at
/// the top and of the workout dock at the bottom (board 4.3), and snaps to
/// the nearest corner after a drag.
class MiniPlayerHost extends StatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  State<MiniPlayerHost> createState() => _MiniPlayerHostState();
}

/// Its own [Overlay] (it sits above the app's Navigator): one entry for the
/// app, one for the floating player, so the player's buttons have tooltips.
class _MiniPlayerHostState extends State<MiniPlayerHost> {
  late final OverlayEntry _app = OverlayEntry(builder: (_) => widget.child);
  final OverlayEntry _mini = OverlayEntry(
    builder: (_) => Consumer(
      builder: (context, ref, _) {
        final mini = ref.watch(miniPlayerProvider);
        return Stack(
          children: [
            if (mini != null)
              _Floating(
                key: ValueKey('${mini.video.id}@${mini.video.start}'),
                mini: mini,
              ),
          ],
        );
      },
    ),
  );

  @override
  void didUpdateWidget(MiniPlayerHost old) {
    super.didUpdateWidget(old);
    if (old.child != widget.child) _app.markNeedsBuild();
  }

  @override
  void dispose() {
    _app
      ..remove()
      ..dispose();
    _mini
      ..remove()
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Overlay(initialEntries: [_app, _mini]);
}

class _Floating extends ConsumerStatefulWidget {
  const new({required this.mini, super.key});

  final MiniPlayerState mini;

  @override
  ConsumerState<_Floating> createState() => _FloatingState();
}

class _FloatingState extends ConsumerState<_Floating> {
  final _playback = VideoPlayback();
  Offset _drag = Offset.zero;

  @override
  void dispose() {
    _playback.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final reserve = ref.watch(miniPlayerBottomReserveProvider);
    // An empty Stack lets taps through to the app; only the card takes them.
    final margin = AppDimens.md;
    final top = media.padding.top + kToolbarHeight + AppDimens.sm2;
    final bottom = media.padding.bottom + reserve + AppDimens.sm2;
    final corner = widget.mini.corner;
    final atTop = corner == MiniCorner.topStart || corner == MiniCorner.topEnd;
    final atStart =
        corner == MiniCorner.topStart || corner == MiniCorner.bottomStart;
    final actions = ref.read(videoActionsProvider);
    final mini = widget.mini;
    final view = MiniPlayerView(
      video: mini.video,
      title: mini.info?.title ?? '',
      surface: ref.watch(videoSurfaceProvider),
      playback: _playback,
      onExpand: () {
        final navigator = rootNavigatorKey.currentContext;
        ref.read(miniPlayerProvider.notifier).close();
        if (navigator == null) return;
        unawaited(
          actions.play(
            navigator,
            atSecond(mini.video, _playback.seconds),
            mini.source,
            info: mini.info,
          ),
        );
      },
      onClose: () => ref.read(miniPlayerProvider.notifier).close(),
    );
    return PositionedDirectional(
      top: atTop ? top : null,
      bottom: atTop ? null : bottom,
      start: atStart ? margin : null,
      end: atStart ? null : margin,
      child: Transform.translate(
        offset: _drag,
        child: GestureDetector(
          key: const Key('mini_player_drag'),
          onPanUpdate: (d) => setState(() => _drag += d.delta),
          onPanEnd: (_) {
            final box = context.findRenderObject() as RenderBox?;
            final size = box?.size ?? Size.zero;
            final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
            final centre = origin + size.center(Offset.zero);
            ref
                .read(miniPlayerProvider.notifier)
                .moveTo(
                  nearestCorner(
                    x: centre.dx,
                    y: centre.dy,
                    width: media.size.width,
                    height: media.size.height,
                    rtl: rtl,
                  ),
                );
            setState(() => _drag = Offset.zero);
          },
          child: view,
        ),
      ),
    );
  }
}
