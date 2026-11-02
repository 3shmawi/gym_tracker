import 'package:meta/meta.dart';

/// The 6-character gym invite code printed under the QR and carried by
/// `https://azmm.pages.dev/join/<code>` and `azm://join/<code>`.
///
/// A code from a link, a QR or the keyboard is untrusted text: it is only
/// ever used after [InviteCode.tryParse] accepted it. Keep the alphabet in
/// sync with the SQL generator, the Edge Function and `website/assets/join-code.js`.
@immutable
class InviteCode {
  const new _(this.value);

  /// The 31 letters and digits a code is made of (no `0 O 1 I L`).
  static const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const length = 6;

  static final _ascii = RegExp(r'^[A-Za-z0-9]+$');
  static final _valid = RegExp('^[$alphabet]{$length}\$');

  /// Always 6 characters of [alphabet], upper case.
  final String value;

  /// [raw] cleaned and checked, or null when it is not a code. Spaces around
  /// it are ignored and case does not matter. Non-ASCII text is refused
  /// before upper-casing, so "ß" or "ſ" can never fold into a letter.
  static InviteCode? tryParse(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.length != length || !_ascii.hasMatch(text)) return null;
    final code = text.toUpperCase();
    return _valid.hasMatch(code) ? InviteCode._(code) : null;
  }

  /// The only places a scanned QR may point to. Anything else (another host,
  /// a query, a fragment, extra path pieces, a port, user info) is refused,
  /// so a poster with a look-alike QR cannot make the app do anything.
  static const linkHost = 'azmm.pages.dev';
  static const _maxScanLength = 200;

  /// The code in a scanned QR: `https://azmm.pages.dev/join/<code>`,
  /// `azm://join/<code>` or the bare code. Null for everything else.
  static InviteCode? fromScan(String? raw) {
    if (raw == null) return null;
    final text = raw.trim();
    if (text.isEmpty || text.length > _maxScanLength) return null;
    if (!text.contains(':')) return tryParse(text);
    final uri = Uri.tryParse(text);
    if (uri == null || uri.hasQuery || uri.hasFragment || uri.userInfo != '') {
      return null;
    }
    if (uri.hasPort && uri.port != 0) return null;
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments;
    switch (scheme) {
      case 'https':
        if (host != linkHost || uri.hasPort) return null;
        if (segments.length != 2 || segments.first != 'join') return null;
        return tryParse(segments.last);
      case 'azm':
        if (host != 'join' || segments.length != 1) return null;
        return tryParse(segments.single);
      default:
        return null;
    }
  }

  /// What a person may type: letters and digits of the alphabet only,
  /// upper-cased, at most [length] characters. For text fields.
  static String clean(String input) {
    final out = StringBuffer();
    for (final unit in input.codeUnits) {
      // ASCII only, then upper-case: "ß" or "ſ" must not fold into letters.
      if (unit > 127) continue;
      final char = String.fromCharCode(unit).toUpperCase();
      if (alphabet.contains(char)) out.write(char);
      if (out.length == length) break;
    }
    return out.toString();
  }

  @override
  bool operator ==(Object other) => other is InviteCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  /// Never print a code in a log: this is deliberately not the value.
  @override
  String toString() => 'InviteCode(***)';
}
