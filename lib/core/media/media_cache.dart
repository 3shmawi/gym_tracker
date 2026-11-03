import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// Loads the bytes of a picture by URL; tests pass their own.
typedef MediaFetch = Future<Uint8List> Function(Uri url);

/// The phone's cache of downloaded pictures (exercise pictures now, video
/// thumbnails later): files only, no personal data, at most [maxFiles] files,
/// each at most [maxBytes]. A picture that was loaded once shows again
/// offline, even after its HTTP validity ran out.
///
/// Only hosts in [allowedHosts] and `https` are fetched: the URLs come from
/// our own builders, this is the second line of defense.
abstract final class MediaCache {
  static const cacheKey = 'azm_media';
  static const maxFiles = 400;
  static const int maxBytes = 2 * 1024 * 1024;
  static const Set<String> allowedHosts = {
    'res.cloudinary.com',
    // YouTube video thumbnails (the temporary cache the owner chose).
    'i.ytimg.com',
  };

  static final CacheManager _manager = CacheManager(
    Config(
      cacheKey,
      // Files nobody opened for this long are removed.
      stalePeriod: const Duration(days: 60),
      maxNrOfCacheObjects: maxFiles,
    ),
  );

  static bool isAllowed(Uri url) =>
      url.scheme == 'https' &&
      allowedHosts.contains(url.host) &&
      !url.hasPort &&
      url.userInfo.isEmpty;

  /// The picture's bytes: fresh from the cache, else downloaded, else (offline
  /// or a failed request) the cached copy even when stale. Throws when there
  /// is nothing, so the image shows its fallback.
  static Future<Uint8List> fetch(Uri url) async {
    if (!isAllowed(url)) throw ArgumentError.value(url.host, 'url', 'host');
    final key = url.toString();
    final cached = await _manager.getFileFromCache(key);
    if (cached != null && cached.validTill.isAfter(DateTime.now())) {
      return await _read(cached);
    }
    try {
      final info = await _manager.downloadFile(key, key: key);
      return await _read(info);
    } on Object {
      if (cached != null) return await _read(cached);
      rethrow;
    }
  }

  static Future<Uint8List> _read(FileInfo info) async {
    final file = info.file;
    final length = await file.length();
    if (length == 0 || length > maxBytes) {
      throw StateError('picture size out of range');
    }
    return await file.readAsBytes();
  }

  /// Removes every cached picture (e.g. when the account is deleted).
  static Future<void> clear() => _manager.emptyCache();
}

/// An [ImageProvider] that loads through [MediaCache] (or [fetch] in tests).
/// Two providers with the same URL are the same image.
@immutable
class CachedMediaImage extends ImageProvider<CachedMediaImage> {
  const new(this.url, {this.fetch = MediaCache.fetch});

  final Uri url;
  final MediaFetch fetch;

  @override
  Future<CachedMediaImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<CachedMediaImage>(this);

  @override
  ImageStreamCompleter loadImage(
    CachedMediaImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: url.path,
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    final bytes = await fetch(url);
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return await decode(buffer);
  }

  @override
  bool operator ==(Object other) =>
      other is CachedMediaImage && other.url == url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'CachedMediaImage(${url.path})';
}
