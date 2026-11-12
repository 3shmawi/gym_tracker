/// What a person may type into the email and code boxes. The server checks
/// again; this only stops what is plainly not an email or a code before a
/// request is made.
abstract final class EmailRules {
  // Spaces, control characters and the invisible marks that can reorder text.
  static final RegExp _unsafe = RegExp(
    r'[\s\u0000-\u001F\u007F-\u009F\u200B-\u200F'
    r'\u202A-\u202E\u2066-\u2069]',
  );

  // Characters an address cannot hold unquoted: markup, brackets, quotes and
  // separators. (Letters of any script are fine.)
  static final RegExp _forbidden = RegExp(r'[<>()\[\]\\,;:"]');

  /// RFC 5321: an address is at most 254 characters.
  static const maxLength = 254;

  /// The text as an address, or null: one `@`, something on both sides, a dot
  /// in the domain that is not at its edge, no spaces, control or invisible
  /// characters, no two dots in a row.
  static String? clean(String raw) {
    final text = raw.trim();
    if (text.isEmpty || text.length > maxLength) return null;
    if (_unsafe.hasMatch(text) || _forbidden.hasMatch(text)) return null;
    final parts = text.split('@');
    if (parts.length != 2) return null;
    final (local, domain) = (parts[0], parts[1]);
    if (local.isEmpty || local.length > 64 || local.startsWith('.')) {
      return null;
    }
    if (local.endsWith('.') || text.contains('..')) return null;
    if (!domain.contains('.') ||
        domain.startsWith('.') ||
        domain.endsWith('.') ||
        domain.startsWith('-')) {
      return null;
    }
    return text;
  }

  /// The six digits of a code: everything else a paste may bring (spaces,
  /// dashes, letters) is dropped, and only the first six digits count.
  static String code(String input) {
    final digits = input.replaceAll(RegExp('[^0-9]'), '');
    return digits.length > 6 ? digits.substring(0, 6) : digits;
  }

  static bool isCode(String input) => RegExp(r'^[0-9]{6}$').hasMatch(input);
}
