import 'package:flutter/services.dart';

/// Keeps the screen on while a Move games round runs: the phone lies on the
/// floor, untouched, and would lock in 30 s. iOS: the idle timer; Android:
/// `FLAG_KEEP_SCREEN_ON`. One flag, so no package (MainActivity.kt,
/// AppDelegate.swift).
abstract interface class ScreenAwake {
  Future<void> keepOn({required bool on});
}

class ChannelScreenAwake implements ScreenAwake {
  const new();

  static const channel = MethodChannel('azm/screen_awake');

  /// Never fails the round: a phone that cannot keep the screen on just
  /// locks as usual.
  @override
  Future<void> keepOn({required bool on}) async {
    try {
      await channel.invokeMethod<void>('keepOn', on);
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }
}
