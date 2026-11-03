import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/widgets.dart';

/// Links are untrusted input. go_router 18.1.2 throws a `FormatException`
/// when a link's path or query has invalid percent-encoding (`?day=%FF`),
/// inside its own code and for every route, so no route can handle it. This
/// guard looks at a link first and drops one that cannot be decoded; the app
/// stays where it is (a link that opens nothing).
///
/// Two entry points: a link while the app runs ([install] adds an observer
/// that sees it before go_router does) and the link that starts the app
/// ([initialLocation]).
abstract final class LinkGuard {
  /// True when [uri] decodes: its path segments, query and fragment.
  static bool isSafe(Uri uri) {
    try {
      _decode(uri);
      return true;
    } on FormatException {
      return false;
    }
  }

  /// Everything go_router reads from a link, decoded. Each part decodes
  /// lazily, so reading it is the check.
  static List<String> _decode(Uri uri) => [
    ...uri.pathSegments,
    ...uri.queryParametersAll.keys,
    for (final values in uri.queryParametersAll.values) ...values,
    Uri.decodeComponent(uri.fragment),
  ];

  /// [raw] as a location go_router may use, or null when it cannot be parsed
  /// or decoded.
  static String? safeLocation(String raw) {
    try {
      final uri = Uri.parse(raw);
      if (!isSafe(uri)) return null;
      return (uri.hasEmptyPath ? uri.replace(path: '/') : uri).toString();
    } on FormatException {
      return null;
    }
  }

  /// Where the app starts: the link that opened it, or home when there is
  /// none or it is not safe.
  static String initialLocation({String? platformDefault, String home = '/'}) {
    final raw = platformDefault ?? PlatformDispatcher.instance.defaultRouteName;
    return safeLocation(raw) ?? home;
  }

  static _Observer? _observer;

  /// Starts dropping unsafe links. Call once, before the app builds its
  /// router (observers are asked in the order they were added). Safe to call
  /// again.
  static void install() {
    if (_observer != null) return;
    _observer = _Observer();
    WidgetsBinding.instance.addObserver(_observer!);
  }

  /// What [install] adds, for tests that ask it about a link directly.
  @visibleForTesting
  static WidgetsBindingObserver get observerForTest => _Observer();

  /// For tests.
  @visibleForTesting
  static void uninstall() {
    final observer = _observer;
    if (observer == null) return;
    WidgetsBinding.instance.removeObserver(observer);
    _observer = null;
  }
}

class _Observer with WidgetsBindingObserver {
  /// Returning true says "handled": the link goes no further.
  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async => !LinkGuard.isSafe(routeInformation.uri);
}

/// For every `WidgetsBindingObserver` of the app that is not about links:
/// Flutter's default `didPushRouteInformation` decodes the link's query and
/// throws on broken percent-encoding, once per observer. This says "not
/// mine" without looking at the link. `test/security/` checks that every
/// observer in `lib/` uses it.
mixin IgnoresLinks on WidgetsBindingObserver {
  @override
  Future<bool> didPushRouteInformation(
    RouteInformation routeInformation,
  ) async => false;
}
