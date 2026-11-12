import 'dart:convert';

/// Reading what the phone stored. A value of the wrong shape (hand-edited,
/// an old format) becomes a [FormatException], i.e. a validation failure, not
/// an unknown crash.
T parseStored<T>(T Function() parse) {
  try {
    return parse();
    // A cast failure in our own parser is data, not a bug: report it as one.
    // ignore: avoid_catching_errors
  } on TypeError catch (error) {
    throw FormatException('stored workout data is invalid: $error');
  }
}

Map<String, Object?> decodeStoredMap(String raw) =>
    asStoredMap(jsonDecode(raw));

Map<String, Object?> asStoredMap(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('expected a JSON object');
  }
  return value;
}
