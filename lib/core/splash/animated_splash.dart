import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:gym_tracker/core/monitoring/monitoring.dart';
import 'package:gym_tracker/core/splash/splash_play_log.dart';
import 'package:gym_tracker/core/theme/app_colors.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';

/// The Flutter splash that follows the native one (the static mark on
/// [AppColors.darkBg]): the logo animation, figures only, centred at the
/// native mark's size so the hand-off is seamless.
///
/// It never delays start-up: it shows while [ready] (the app's start-up
/// work) runs, and switches to [app] as soon as both the animation and
/// [ready] are done. The full animation plays on the first launch of the
/// day ([playLog]); after that the static logo stays only while loading.
/// Reduce Motion: the static logo. A failed [ready] still opens the app.
class AnimatedSplash extends StatefulWidget {
  const new({
    required this.ready,
    required this.app,
    this.playLog = const SharedPrefsSplashPlayLog(),
    this.clock = DateTime.now,
    super.key,
  });

  final Future<void> ready;
  final WidgetBuilder app;
  final SplashPlayLog playLog;
  final DateTime Function() clock;

  /// Longest wait for the play log before falling back to the short splash.
  static const playLogTimeout = Duration(milliseconds: 300);

  /// The cross-fade from the splash into the app.
  static const handOff = Duration(milliseconds: 250);

  @override
  State<AnimatedSplash> createState() => _AnimatedSplashState();
}

enum _Play { deciding, full, short }

class _AnimatedSplashState extends State<AnimatedSplash> {
  _Play _play = _Play.deciding;
  var _animationDone = false;
  var _loaded = false;

  bool get _open => _loaded && _animationDone;

  @override
  void initState() {
    super.initState();
    unawaited(_decide());
    unawaited(_load());
  }

  Future<void> _decide() async {
    var full = false;
    try {
      full = await widget.playLog
          .shouldPlayFull(widget.clock())
          .timeout(AnimatedSplash.playLogTimeout);
    } on Object catch (error, stackTrace) {
      if (error is! TimeoutException) {
        unawaited(Monitoring.captureException(error, stackTrace));
      }
    }
    if (!mounted) return;
    setState(() {
      _play = full ? _Play.full : _Play.short;
      if (!full) _animationDone = true;
    });
  }

  Future<void> _load() async {
    try {
      await widget.ready;
    } on Object catch (error, stackTrace) {
      unawaited(Monitoring.captureException(error, stackTrace));
    }
    if (mounted) setState(() => _loaded = true);
  }

  void _onAnimationDone() {
    if (mounted) setState(() => _animationDone = true);
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : AnimatedSplash.handOff,
        child: _open
            ? KeyedSubtree(
                key: const ValueKey('app'),
                child: Builder(builder: widget.app),
              )
            : ColoredBox(
                key: const ValueKey('splash'),
                color: AppColors.darkBg,
                child: Center(
                  child: AzmLogoAnimation(
                    key: ValueKey(_play),
                    size: AzmLogoAnimation.nativeSplashSize,
                    // Until it knows, and on the short splash: the static
                    // logo, exactly what the native splash shows.
                    progress: _play == _Play.full ? null : 1,
                    onCompleted: _play == _Play.full ? _onAnimationDone : null,
                  ),
                ),
              ),
      ),
    );
  }
}
