import 'package:meta/meta.dart';

/// A YouTube video the app may play: only the 11-character id and optional
/// start / end seconds. Never a URL: the app builds its own player and links
/// from the id (docs/features/exercise_videos.md → "Video links").
@immutable
class YouTubeVideoRef {
  const new(this.id, {this.start, this.end});

  /// 11 characters of `[A-Za-z0-9_-]`.
  static final idPattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  /// The longest start or end we accept (12 hours).
  static const maxSeconds = 43200;

  final String id;
  final int? start;
  final int? end;

  /// A valid id and times (0 ≤ start < end ≤ 12 h); the database checks the
  /// same rules for the gym's videos.
  static bool isValid(String id, {int? start, int? end}) =>
      idPattern.hasMatch(id) &&
      (start == null || (start >= 0 && start <= maxSeconds)) &&
      (end == null || (end > 0 && end <= maxSeconds)) &&
      (start == null || end == null || end > start);

  /// The YouTube page of the video (for "Open in YouTube").
  Uri get watchUrl => Uri(
    scheme: 'https',
    host: 'www.youtube.com',
    path: '/watch',
    queryParameters: {'v': id, if (start != null && start! > 0) 't': '$start'},
  );

  @override
  bool operator ==(Object other) =>
      other is YouTubeVideoRef &&
      other.id == id &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(id, start, end);

  @override
  String toString() => 'YouTubeVideoRef($id, start: $start, end: $end)';
}

/// Turns a link a captain pastes into a [YouTubeVideoRef], or null.
///
/// The rules (also in docs/features/exercise_videos.md, with the shared test
/// vectors `docs/features/youtube_link_vectors.json` the dashboard runs too):
/// - `https` only; no user info, no port; at most 2048 characters; leading and
///   trailing spaces are trimmed.
/// - Hosts: `youtube.com`, `www.youtube.com`, `m.youtube.com`, `youtu.be`,
///   `youtube-nocookie.com`, `www.youtube-nocookie.com` (case-insensitive).
///   Anything else is refused, including `music.youtube.com` (music, not
///   how-to clips), look-alikes and sub-domains of other sites.
/// - Paths: `/watch?v=ID`, `youtu.be/ID`, `/shorts/ID`, `/embed/ID` (the only
///   path on the nocookie hosts). `/live/ID` is refused: a stream is not a
///   how-to clip, and a finished one has a `/watch` link.
/// - The id is exactly 11 of `[A-Za-z0-9_-]`. No `%` anywhere in the link
///   (no percent-encoding), no backslash, no space or non-ASCII inside.
/// - Start: `t=` (`90`, `90s`, `1m30s`, `1h2m3s`) or `start=` (seconds);
///   end: `end=` (seconds). Out of range or end ≤ start: refused.
/// - Other query parameters (`si`, `feature`, `list`, …) are ignored.
abstract final class YouTubeLink {
  static const maxLength = 2048;

  static const _watchHosts = {
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
  };
  static const _shortHost = 'youtu.be';
  static const _noCookieHosts = {
    'youtube-nocookie.com',
    'www.youtube-nocookie.com',
  };

  static final _time = RegExp(
    r'^(?:(\d{1,2})h)?(?:(\d{1,4})m)?(?:(\d{1,5})s?)?$',
  );
  static final _seconds = RegExp(r'^\d{1,5}$');

  static YouTubeVideoRef? parse(String input) {
    final text = input.trim();
    if (text.isEmpty || text.length > maxLength) return null;
    // Backslashes, spaces, controls and non-ASCII are never part of a link
    // we accept (look-alike hosts, smuggled paths).
    if (!RegExp(r'^[\x21-\x7E]+$').hasMatch(text) ||
        text.contains(r'\') ||
        // Percent-encoding: Uri.parse decodes `%77` to `w`, so an encoded id
        // or path would pass as a different one.
        text.contains('%')) {
      return null;
    }
    final Uri uri;
    try {
      uri = Uri.parse(text);
    } on FormatException {
      return null;
    }
    if (uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.host.isEmpty) {
      return null;
    }
    final host = uri.host.toLowerCase();
    final segments = uri.path.split('/').where((s) => s.isNotEmpty).toList();

    String? id;
    if (_watchHosts.contains(host)) {
      if (segments.length == 1 && segments.first == 'watch') {
        id = _single(uri, 'v');
      } else if (segments.length == 2 &&
          (segments.first == 'shorts' || segments.first == 'embed')) {
        id = segments[1];
      }
    } else if (host == _shortHost) {
      if (segments.length == 1) id = segments.first;
    } else if (_noCookieHosts.contains(host)) {
      if (segments.length == 2 && segments.first == 'embed') id = segments[1];
    }
    if (id == null || !YouTubeVideoRef.idPattern.hasMatch(id)) return null;

    final t = _single(uri, 't');
    final startParam = _single(uri, 'start');
    final endParam = _single(uri, 'end');
    if (t != null && startParam != null) return null;
    final start = t != null
        ? _parseTime(t)
        : startParam != null
        ? _parseSeconds(startParam)
        : null;
    final end = endParam == null ? null : _parseSeconds(endParam);
    if ((t != null || startParam != null) && start == null) return null;
    if (endParam != null && end == null) return null;
    final zeroStart = start == 0 ? null : start;
    if (!YouTubeVideoRef.isValid(id, start: zeroStart, end: end)) return null;
    return YouTubeVideoRef(id, start: zeroStart, end: end);
  }

  /// The one value of [name]; null when absent, and refused (the empty
  /// string, never an id) when given twice.
  static String? _single(Uri uri, String name) {
    final all = uri.queryParametersAll[name];
    if (all == null || all.isEmpty) return null;
    if (all.length > 1) return '';
    return all.first;
  }

  static int? _parseSeconds(String value) =>
      _seconds.hasMatch(value) ? int.parse(value) : null;

  static int? _parseTime(String value) {
    if (value.isEmpty) return null;
    final m = _time.firstMatch(value);
    if (m == null) return null;
    final h = int.parse(m.group(1) ?? '0');
    final min = int.parse(m.group(2) ?? '0');
    final s = int.parse(m.group(3) ?? '0');
    return h * 3600 + min * 60 + s;
  }
}
