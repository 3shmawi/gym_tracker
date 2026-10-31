import 'package:flutter/material.dart';

/// The user's app-wide preferences.
@immutable
class AppSettings {
  const new({this.locale, this.themeMode = ThemeMode.system});

  /// `null` means "follow the device language".
  final Locale? locale;
  final ThemeMode themeMode;

  AppSettings copyWith({ValueGetter<Locale?>? locale, ThemeMode? themeMode}) {
    return AppSettings(
      locale: locale != null ? locale() : this.locale,
      themeMode: themeMode ?? this.themeMode,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          other.locale == locale &&
          other.themeMode == themeMode;

  @override
  int get hashCode => Object.hash(locale, themeMode);
}
