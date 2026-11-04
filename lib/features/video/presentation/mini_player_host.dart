import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/router/app_router.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/features/video/presentation/mini_player.dart';
import 'package:gym_tracker/features/video/presentation/video_playback.dart';
import 'package:gym_tracker/features/video/presentation/video_providers.dart';
import 'package:gym_tracker/features/video/presentation/widgets/mini_player_view.dart';
import 'package:gym_tracker/l10n/l10n.dart';

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

  /// Hidden at the screen's edge, a tab showing where it is. Paused: a
  /// player that isn't on screen must not play (YouTube Developer
  /// Policies, docs/decisions/video_outside_app.md).
  bool _docked = false;

  @override
  void dispose() {
    _playback.dispose();
    super.dispose();
  }

  void _dock() {
    _playback.pause();
    setState(() => _docked = true);
  }

  void _undock() {
    setState(() => _docked = false);
    _playback.play();
  }

  /// Where the card's centre is now, the drag included.
  Offset _centre() {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return Offset.zero;
    // The translation moves only what is painted, not the box's own
    // position: add it, or the card always snaps back where it started.
    return box.localToGlobal(Offset.zero) +
        box.size.center(Offset.zero) +
        _drag;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final media = MediaQuery.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final reserve = ref.watch(miniPlayerBottomReserveProvider);
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
    final card = PositionedDirectional(
      top: atTop ? top : null,
      bottom: atTop ? null : bottom,
      start: atStart ? margin : null,
      end: atStart ? null : margin,
      child: Offstage(
        offstage: _docked,
        child: Transform.translate(
          offset: _drag,
          child: Semantics(
            customSemanticsActions: {
              CustomSemanticsAction(label: l10n.miniPlayerHide): _dock,
            },
            child: GestureDetector(
              key: const Key('mini_player_drag'),
              onPanUpdate: (d) => setState(() => _drag += d.delta),
              onPanEnd: (_) {
                final centre = _centre();
                final width = media.size.width;
                // Dragged past a side: hide it there, a tab at the edge.
                final pastLeft = centre.dx < 0;
                final pastRight = centre.dx > width;
                ref
                    .read(miniPlayerProvider.notifier)
                    .moveTo(
                      nearestCorner(
                        x: pastLeft
                            ? 0
                            : pastRight
                            ? width
                            : centre.dx,
                        y: centre.dy,
                        width: width,
                        height: media.size.height,
                        rtl: rtl,
                      ),
                    );
                setState(() => _drag = Offset.zero);
                if (pastLeft || pastRight) _dock();
              },
              child: view,
            ),
          ),
        ),
      ),
    );
    if (!_docked) return card;
    return Stack(
      children: [
        card,
        PositionedDirectional(
          top: atTop ? top : null,
          bottom: atTop ? null : bottom,
          start: atStart ? 0 : null,
          end: atStart ? null : 0,
          child: _EdgeTab(
            atStart: atStart,
            label: l10n.miniPlayerShow,
            onTap: _undock,
          ),
        ),
      ],
    );
  }
}

/// The hidden mini player's handle at the screen's edge (48 × 72): tap to
/// bring the video back.
class _EdgeTab extends StatelessWidget {
  const new({required this.atStart, required this.label, required this.onTap});

  final bool atStart;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = Radius.circular(AppDimens.radiusMd);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: scheme.primary,
        borderRadius: BorderRadiusDirectional.horizontal(
          start: atStart ? Radius.zero : radius,
          end: atStart ? radius : Radius.zero,
        ),
        child: InkWell(
          key: const Key('mini_player_tab'),
          onTap: onTap,
          child: SizedBox(
            width: AppDimens.minTouchTarget,
            height: AppDimens.minTouchTarget * 1.5,
            child: Center(
              child: Container(
                width: 4,
                height: AppDimens.minTouchTarget * 0.6,
                decoration: BoxDecoration(
                  color: scheme.onPrimary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
