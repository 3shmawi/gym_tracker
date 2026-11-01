import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Spacing, radii and sizes, scaled to the screen. Never hard-code paddings
/// in widgets — use these.
///
/// Sizes follow the screen width, but the scale is clamped to
/// [minScale]–[maxScale]: a small phone shrinks a little, a large phone
/// grows a little, and a tablet gets more room instead of a zoomed-in
/// phone UI. `test/helpers/ui_check.dart` checks this on every screen.
abstract final class AppDimens {
  /// The size of the design frame the UI was drawn on.
  static const designSize = Size(375, 812);

  static const minScale = 0.9;
  static const maxScale = 1.15;

  /// Smallest touch target (Android 48 dp, iOS 44 pt).
  static const minTouchTarget = 48.0;

  /// Screen width / design width, clamped.
  static double get scale => ScreenUtil().scaleWidth.clamp(minScale, maxScale);

  /// [value] from the design frame, scaled for this screen.
  static double scaled(double value) => value * scale;

  static double get xs => scaled(4);
  static double get sm => scaled(8);
  static double get md => scaled(16);
  static double get lg => scaled(24);
  static double get sm2 => scaled(12);
  static double get xl => scaled(32);

  static double get radiusSm => scaled(8);
  static double get radiusMd => scaled(12);
  static double get radiusLg => scaled(20);
  static double get radiusXl => scaled(24);
  static double get radiusSheet => scaled(32);
  static const radiusFull = 999.0;

  static double get iconMd => scaled(24);

  /// Content never gets wider than this: on a tablet the screen is centered
  /// instead of stretched edge to edge.
  static const maxContentWidth = 600.0;

  /// Logging controls (stepper keys): bigger than [minTouchTarget] for a
  /// sweaty thumb between sets.
  static double get targetLog => math.max(56, scaled(56));

  /// Height of the big primary button (log a set, start workout).
  static double get ctaHeight => math.max(56, scaled(60));

  /// Never below [minTouchTarget], even on the smallest phone.
  static double get buttonHeight => math.max(minTouchTarget, scaled(48));

  /// The looping logo in `LoadingView` (`AzmLogoAnimation`, figures only):
  /// inline in a row or list item, inside a card, and a whole screen. The
  /// screen size is the native splash mark's size, so a screen that loads
  /// right after start-up looks like the splash.
  /// The level figure on the home screen's level card (60×70 box).
  static double get levelFigure => scaled(48);

  static double get loadingInline => scaled(48);
  static double get loadingCard => scaled(96);
  static double get loadingScreen => scaled(166);
}

/// Sets up screen scaling for the app (and for tests, so they measure the
/// same sizes as a real device).
class AppScreenScale extends StatelessWidget {
  const new({required this.builder, super.key});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) => ScreenUtilInit(
    designSize: AppDimens.designSize,
    minTextAdapt: true,
    splitScreenMode: true,
    builder: (context, _) => builder(context),
  );
}
