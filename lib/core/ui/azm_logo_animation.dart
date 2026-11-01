import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';
import 'package:gym_tracker/core/ui/azm_logo_painter.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// The approved Azm logo animation (docs/design/motion/): the light lift,
/// the heavy lift, the flex, then the static logo. Figures only, no text.
///
/// One [AnimationController] drives every part. With Reduce Motion
/// (`MediaQuery.disableAnimations`) it shows the static logo. To the screen
/// reader it is one element with one label ([semanticsLabel], by default
/// "Loading").
///
/// The background is transparent.
class AzmLogoAnimation extends StatefulWidget {
  const new({
    required this.size,
    this.loop = false,
    this.duration = defaultDuration,
    this.progress,
    this.semanticsLabel,
    this.onCompleted,
    super.key,
  });

  /// Side of the square it paints. The static logo fills about 2/3 of it,
  /// centred; the rest is room for the bars that step aside.
  final double size;

  /// Plays again and again (loading) instead of once (splash).
  final bool loop;

  final Duration duration;

  /// Shows this one frame (0 → 1) without animating; 1 is the static
  /// logo. For screenshots and the short splash.
  final double? progress;

  final String? semanticsLabel;

  /// Called once when a non-looping animation reaches the static logo (at
  /// once with Reduce Motion or a fixed [progress]).
  final VoidCallback? onCompleted;

  static const defaultDuration = Duration(milliseconds: 2600);

  /// The size whose static logo matches the native splash mark exactly
  /// (the 192-pt splash image, mark 75 of its 100 units at 5.95 px/unit
  /// on the 768-px export), so the hand-off is seamless.
  static const nativeSplashSize = 166.0;

  @override
  State<AzmLogoAnimation> createState() => _AzmLogoAnimationState();
}

class _AzmLogoAnimationState extends State<AzmLogoAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: widget.duration)
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) _complete();
        });
  bool _completed = false;
  bool _reduceMotion = false;

  bool get _static => _reduceMotion || widget.progress != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _sync();
  }

  @override
  void didUpdateWidget(AzmLogoAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (oldWidget.loop != widget.loop ||
        oldWidget.progress != widget.progress) {
      _sync();
    }
  }

  void _sync() {
    if (_static) {
      _controller.stop();
      WidgetsBinding.instance.addPostFrameCallback((_) => _complete());
    } else if (widget.loop) {
      _controller.repeat();
    } else if (!_controller.isAnimating && !_completed) {
      _controller.forward();
    }
  }

  void _complete() {
    if (_completed || !mounted || widget.loop && !_static) return;
    _completed = true;
    widget.onCompleted?.call();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label =
        widget.semanticsLabel ??
        (Localizations.of<AppLocalizations>(context, AppLocalizations) ??
                lookupAppLocalizations(_deviceLocale()))
            .loading;
    return Semantics(
      label: label,
      image: true,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: widget.size,
        child: _static
            ? CustomPaint(painter: AzmLogoPainter(widget.progress ?? 1))
            : AnimatedBuilder(
                animation: _controller,
                builder: (context, _) =>
                    CustomPaint(painter: AzmLogoPainter(_controller.value)),
              ),
      ),
    );
  }

  /// Before the app's localizations exist (the splash): the device
  /// language, if the app has it.
  static Locale _deviceLocale() {
    for (final locale in PlatformDispatcher.instance.locales) {
      for (final supported in AppLocalizations.supportedLocales) {
        if (supported.languageCode == locale.languageCode) return supported;
      }
    }
    return const Locale('en');
  }
}
