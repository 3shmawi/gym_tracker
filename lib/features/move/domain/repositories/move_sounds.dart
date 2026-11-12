/// The game's short sounds (docs/designs/move_games.md, decision 6). They
/// play alongside the member's music and never stop it.
abstract interface class MoveSounds {
  /// Loads the sounds; safe to call more than once.
  Future<void> load();

  /// A block lands.
  void rep();

  /// Every fifth block.
  void milestone();

  Future<void> dispose();
}

/// No sound (widget tests, and until the app has started).
final class SilentMoveSounds implements MoveSounds {
  const new();

  @override
  Future<void> load() async {}

  @override
  void rep() {}

  @override
  void milestone() {}

  @override
  Future<void> dispose() async {}
}
