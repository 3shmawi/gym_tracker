/// Says the rep count out loud (docs/designs/move_games.md, decision 7).
/// Only a voice on the phone is used: nothing is sent anywhere, and the
/// member's music keeps playing.
abstract interface class MoveVoice {
  /// Gets ready to speak [language] ("ar", "en"). False when this phone has
  /// no voice for it that works offline (the round then plays tones).
  Future<bool> prepare(String language);

  /// Says [count] ("7"), cutting off a count still being spoken.
  void count(int count);

  Future<void> dispose();
}

/// No voice (widget tests, and until the app has started).
final class SilentMoveVoice implements MoveVoice {
  const new({this.available = false});

  /// Tests can pretend a voice exists.
  final bool available;

  @override
  Future<bool> prepare(String language) async => available;

  @override
  void count(int count) {}

  @override
  Future<void> dispose() async {}
}
