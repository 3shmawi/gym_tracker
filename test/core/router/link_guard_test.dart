import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/router/link_guard.dart';

void main() {
  group('LinkGuard.isSafe', () {
    test('ordinary links are safe', () {
      for (final raw in [
        '/',
        '/plan/day-1',
        '/library?day=day-1',
        '/library?day=a%20b&day=c',
        '/join/K7M2QX',
        '/x?y=%F0%9F%92%A5',
        '/%E2%9C%93',
        '/a#frag%20ment',
        '/a?',
        '/a?b',
        '/a?b=',
      ]) {
        expect(LinkGuard.isSafe(Uri.parse(raw)), isTrue, reason: raw);
      }
    });

    test('broken percent-encoding anywhere is unsafe', () {
      for (final raw in [
        '/library?day=%FF',
        '/library?%FF=1',
        '/library?day=1&day=%C0',
        '/plan/%FF',
        '/plan/%C3',
        '/a#%FF',
        '/library?day=%00%FF',
      ]) {
        expect(LinkGuard.isSafe(Uri.parse(raw)), isFalse, reason: raw);
      }
    });
  });

  group('LinkGuard.safeLocation / initialLocation', () {
    test('a good link is kept, an empty path becomes home', () {
      expect(LinkGuard.safeLocation('/plan?x=1'), '/plan?x=1');
      expect(LinkGuard.safeLocation('?a=b'), '/?a=b');
      expect(LinkGuard.initialLocation(platformDefault: '/plan'), '/plan');
      expect(LinkGuard.initialLocation(platformDefault: '/'), '/');
    });

    test('an unsafe or unparsable link starts the app at home', () {
      for (final raw in [
        '/library?day=%FF',
        '/plan/%FF',
        'http://[::1',
        'ht tp://x',
      ]) {
        expect(
          LinkGuard.initialLocation(platformDefault: raw),
          '/',
          reason: raw,
        );
      }
      expect(
        LinkGuard.initialLocation(platformDefault: '/x?%FF=1', home: '/h'),
        '/h',
      );
    });
  });

  group('the observer', () {
    RouteInformation info(String raw) => RouteInformation(uri: Uri.parse(raw));
    final observer = LinkGuard.observerForTest;

    test('takes a link it cannot decode (nobody else sees it)', () async {
      for (final bad in [
        '/library?day=%FF',
        '/plan/%FF',
        '/join/abc?redirect=%C0%AF',
        '/settings#%FF',
      ]) {
        expect(await observer.didPushRouteInformation(info(bad)), isTrue);
      }
    });

    test('leaves a good link to go_router', () async {
      for (final good in ['/', '/plan', '/library?day=day-1', '/join/K7M2QX']) {
        expect(await observer.didPushRouteInformation(info(good)), isFalse);
      }
    });

    test('is added once, and removed again', () {
      LinkGuard.install();
      LinkGuard.install();
      LinkGuard.uninstall();
      LinkGuard.uninstall();
    });
  });

  test('every observer in lib/ ignores links or is the guard', () {
    // Flutter's default `didPushRouteInformation` throws on a link with
    // broken percent-encoding, once per observer that does not override it.
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true)) {
      if (f is! File || !f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('core/router/link_guard.dart')) continue;
      final text = f.readAsStringSync();
      if (!text.contains('WidgetsBindingObserver')) continue;
      if (!text.contains('IgnoresLinks') &&
          !text.contains('didPushRouteInformation')) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty);
  });
}
