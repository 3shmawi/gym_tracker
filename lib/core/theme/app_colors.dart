import 'package:flutter/material.dart';

/// Raw color tokens from the Design System (docs/design.md). Widgets read
/// theme-dependent colors through `context.palette` (AppPalette) or
/// `Theme.of(context).colorScheme`, never these directly, except brand
/// moments.
abstract final class AppColors {
  /// Brand green: fills (log button, progress). On light backgrounds use
  /// [primaryText] for text, it has the contrast.
  static const primary = Color(0xFF22C55E);
  static const primaryText = Color(0xFF15803D);

  /// Text/icons on a [primary] fill (9.6:1).
  static const onPrimary = Color(0xFF04210F);

  // Dark theme (primary)
  static const darkBg = Color(0xFF07120C);
  static const darkGlow1 = Color(0xFF14532D);
  static const darkGlow2 = Color(0xFF0B3B24);
  static const darkSurface = Color(0xFF141E19);
  static const darkText1 = Color(0xFFF2F7F3);
  static const darkText2 = Color(0xFFA9B8AF);
  static const darkText3 = Color(0xFF7C8B83);
  static const darkUp = Color(0xFF4ADE80);
  static const darkKeep = Color(0xFF93C5FD);
  static const darkDown = Color(0xFFFBBF24);
  static const darkNew = Color(0xFFC4B5FD);
  static const darkError = Color(0xFFF87171);

  // Light theme
  static const lightBg = Color(0xFFEEF4F0);
  static const lightGlow1 = Color(0xFFBBF7D0);
  static const lightGlow2 = Color(0xFFD1FAE5);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightText1 = Color(0xFF0C1610);
  static const lightText2 = Color(0xFF46554C);
  static const lightText3 = Color(0xFF5F6E66);
  static const lightUp = Color(0xFF166534);
  static const lightKeep = Color(0xFF1D4ED8);
  static const lightDown = Color(0xFF92400E);
  static const lightNew = Color(0xFF6D28D9);
  static const lightError = Color(0xFFB91C1C);

  // Semantic, kept for existing callers: the light-theme values.
  static const Color success = lightUp;
  static const Color warning = lightDown;
  static const Color error = lightError;
}
