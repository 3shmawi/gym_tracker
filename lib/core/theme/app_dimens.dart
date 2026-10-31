import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Spacing, radii and sizes, scaled to the screen with flutter_screenutil.
/// Never hard-code paddings in widgets — use these.
abstract final class AppDimens {
  /// The size of the design (Figma) frame the UI was drawn on.
  static const designSize = Size(375, 812);

  static double get xs => 4.w;
  static double get sm => 8.w;
  static double get md => 16.w;
  static double get lg => 24.w;
  static double get xl => 32.w;

  static double get radiusSm => 8.r;
  static double get radiusMd => 12.r;
  static double get radiusLg => 20.r;

  static double get iconMd => 24.r;
  static double get buttonHeight => 48.h;
}
