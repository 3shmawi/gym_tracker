/// What a camera round sounds like. The [id] is stored and sent in
/// analytics; never reuse one.
enum MoveSoundMode {
  /// The count is spoken ("1, 2, 3…") in the app's language, by a voice on
  /// the phone. The default: useful on the floor, 2 m from the screen.
  voice('voice'),

  /// A short tone per rep and another every fifth.
  tones('tones'),

  off('off');

  new(this.id);

  final String id;

  static const MoveSoundMode fallback = voice;

  static MoveSoundMode fromId(Object? id) =>
      values.where((m) => m.id == id).firstOrNull ?? fallback;

  /// What the sound button switches to: voice → tones → off → voice,
  /// skipping the voice when the phone has none for the language.
  MoveSoundMode next({required bool voiceAvailable}) => switch (this) {
    voice => tones,
    tones => off,
    off => voiceAvailable ? voice : tones,
  };

  /// What actually plays: the voice falls back to tones when there is no
  /// voice for the language on this phone.
  MoveSoundMode effective({required bool voiceAvailable}) =>
      this == voice && !voiceAvailable ? tones : this;
}
