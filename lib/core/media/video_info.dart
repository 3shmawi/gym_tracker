import 'dart:async';
import 'dart:convert';

import 'package:gym_tracker/core/media/youtube_link.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether YouTube lets the app play a video in its embedded player.
enum VideoAvailability {
  /// Plays in the app.
  available,

  /// The owner turned embedding off (oEmbed 401/403): "Open in YouTube".
  embedDisabled,

  /// Removed, private or never existed (oEmbed 400/404): "Video unavailable".
  unavailable,
}

/// What the video card shows: from YouTube oEmbed (no API key), kept on the
/// phone for offline use. Never personal data.
@immutable
class VideoInfo {
  const new({
    required this.availability,
    this.title = '',
    this.channel = '',
    this.vertical = false,
  });

  static const maxText = 200;

  /// Control characters and bidi overrides / isolates.
  static final _unsafe = RegExp(
    '[\u0000-\u001F\u007F-\u009F\u202A-\u202E\u2066-\u2069]',
  );

  final VideoAvailability availability;
  final String title;
  final String channel;

  /// A Short (taller than wide).
  final bool vertical;

  /// The thumbnail, built from the id (never a URL from a response).
  static Uri thumbnail(String videoId) =>
      Uri.parse('https://i.ytimg.com/vi/$videoId/hqdefault.jpg');

  Map<String, Object> toJson() => {
    'a': availability.name,
    't': title,
    'c': channel,
    'v': vertical,
  };

  /// The phone's copy; null for anything malformed.
  static VideoInfo? tryParse(Object? json) {
    if (json is! Map) return null;
    final a = VideoAvailability.values
        .where((v) => v.name == json['a'])
        .firstOrNull;
    final t = json['t'];
    final c = json['c'];
    final v = json['v'];
    if (a == null || t is! String || c is! String || v is! bool) return null;
    return VideoInfo(
      availability: a,
      title: clean(t),
      channel: clean(c),
      vertical: v,
    );
  }

  /// Text from YouTube shown as plain text: no control or bidi-override
  /// characters, trimmed, at most [maxText] characters.
  static String clean(String text) {
    final stripped = text
        .replaceAll(_unsafe, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final runes = stripped.runes.toList();
    return runes.length <= maxText
        ? stripped
        : String.fromCharCodes(runes.take(maxText));
  }

  @override
  bool operator ==(Object other) =>
      other is VideoInfo &&
      other.availability == availability &&
      other.title == title &&
      other.channel == channel &&
      other.vertical == vertical;

  @override
  int get hashCode => Object.hash(availability, title, channel, vertical);
}

/// Reads a video's title, channel and shape from YouTube oEmbed.
abstract interface class VideoInfoRepository {
  /// [Failed] only when YouTube could not be asked (offline, timeout); a
  /// removed or non-embeddable video is a [Success] with its availability.
  Future<Result<VideoInfo>> fetch(YouTubeVideoRef video);
}

/// `GET https://www.youtube.com/oembed?format=json&url=<shorts link>`
/// (the `/shorts/` form answers with a vertical size for a Short).
class OEmbedVideoInfoRepository implements VideoInfoRepository {
  new({http.Client? client, this.retries = 1})
    : _client = client ?? http.Client();

  final http.Client _client;
  final int retries;

  static Uri endpoint(String videoId) => Uri.https(
    'www.youtube.com',
    '/oembed',
    {'format': 'json', 'url': 'https://www.youtube.com/shorts/$videoId'},
  );

  @override
  Future<Result<VideoInfo>> fetch(YouTubeVideoRef video) => guard(() async {
    if (!YouTubeVideoRef.idPattern.hasMatch(video.id)) {
      return const VideoInfo(availability: VideoAvailability.unavailable);
    }
    final response = await _client.get(endpoint(video.id));
    switch (response.statusCode) {
      case 200:
        final body = jsonDecode(utf8.decode(response.bodyBytes));
        if (body is! Map) throw const FormatException('oEmbed body');
        final w = body['width'];
        final h = body['height'];
        return VideoInfo(
          availability: VideoAvailability.available,
          title: clean(body['title']),
          channel: clean(body['author_name']),
          vertical: w is num && h is num && h > w,
        );
      case 401 || 403:
        return const VideoInfo(availability: VideoAvailability.embedDisabled);
      case 400 || 404:
        return const VideoInfo(availability: VideoAvailability.unavailable);
      default:
        throw http.ClientException('oEmbed ${response.statusCode}');
    }
  }, retries: retries);

  static String clean(Object? value) =>
      value is String ? VideoInfo.clean(value) : '';
}

/// The phone's copy of each video's info (shared preferences; titles and
/// channel names of public videos, no personal data).
class VideoInfoStore {
  const new(this._prefs);

  final SharedPreferences _prefs;

  static String key(String videoId) => 'video.info.$videoId';

  VideoInfo? load(String videoId) {
    if (!YouTubeVideoRef.idPattern.hasMatch(videoId)) return null;
    final raw = _prefs.getString(key(videoId));
    if (raw == null) return null;
    try {
      return VideoInfo.tryParse(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  Future<void> save(String videoId, VideoInfo info) async {
    if (!YouTubeVideoRef.idPattern.hasMatch(videoId)) return;
    await _prefs.setString(key(videoId), jsonEncode(info.toJson()));
  }
}

/// The info to show: fresh from YouTube (and kept), else the phone's copy,
/// else null (offline and never seen: "Needs internet").
class LoadVideoInfo {
  const new(this._remote, this._store);

  final VideoInfoRepository _remote;
  final VideoInfoStore? _store;

  Future<VideoInfo?> call(YouTubeVideoRef video) async {
    switch (await _remote.fetch(video)) {
      case Success(:final value):
        unawaited(_store?.save(video.id, value));
        return value;
      case Failed():
        return _store?.load(video.id);
    }
  }
}
