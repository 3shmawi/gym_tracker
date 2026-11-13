/// Turns a condition seen frame by frame into a hint shown at most once in a
/// while: the condition must hold for [hold], and the hint is not repeated
/// for [cooldown] or until the condition has gone away and come back.
class HintGate {
  new({
    this.hold = const Duration(milliseconds: 1500),
    this.cooldown = const Duration(seconds: 5),
  });

  final Duration hold;
  final Duration cooldown;

  Duration? _since;
  Duration? _lastShown;
  bool _shownThisTime = false;

  /// True on the frame the hint should be shown.
  bool update({required bool condition, required Duration at}) {
    if (!condition) {
      _since = null;
      _shownThisTime = false;
      return false;
    }
    final since = _since ??= at;
    if (_shownThisTime || at - since < hold) return false;
    final last = _lastShown;
    if (last != null && at - last < cooldown) return false;
    _lastShown = at;
    _shownThisTime = true;
    return true;
  }

  void reset() {
    _since = null;
    _lastShown = null;
    _shownThisTime = false;
  }
}
