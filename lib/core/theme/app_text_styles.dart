import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Every text style in the app. Colors come from the theme, so these only
/// define size, weight and line height.
abstract final class AppTextStyles {
  static TextStyle get display =>
      TextStyle(fontSize: 32.sp, fontWeight: FontWeight.w700, height: 1.2);
  static TextStyle get headline =>
      TextStyle(fontSize: 24.sp, fontWeight: FontWeight.w700, height: 1.3);
  static TextStyle get title =>
      TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w600, height: 1.3);
  static TextStyle get body => TextStyle(fontSize: 14.sp, height: 1.5);
  static TextStyle get label =>
      TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, height: 1.2);
  static TextStyle get caption => TextStyle(fontSize: 12.sp, height: 1.4);
}
