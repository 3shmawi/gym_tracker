import 'package:flutter/foundation.dart';

/// A handle on the YouTube player that is showing: where it is (whole
/// seconds) and whether it is paused. The surface fills it in and attaches
/// its own pause / play, which only call YouTube's IFrame API; nothing is
/// drawn over the player. Used to carry a video from the sheet to the mini
/// player at the same second (stage V-C).
class VideoPlayback extends ChangeNotifier {
  int _seconds = 0;
  bool _paused = false;
  VoidCallback? _pause;
  VoidCallback? _play;

  int get seconds => _seconds;
  bool get paused => _paused;

  /// The surface reports what YouTube's player says.
  void report({int? seconds, bool? paused}) {
    final s = seconds ?? _seconds;
    final p = paused ?? _paused;
    if (s == _seconds && p == _paused) return;
    _seconds = s < 0 ? 0 : s;
    _paused = p;
    notifyListeners();
  }

  void attach({required VoidCallback pause, required VoidCallback play}) {
    _pause = pause;
    _play = play;
  }

  void detach() {
    _pause = null;
    _play = null;
  }

  void pause() => _pause?.call();
  void play() => _play?.call();
}
