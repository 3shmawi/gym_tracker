import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/captcha/turnstile_page.dart';

void main() {
  group('site key', () {
    test('only plain keys reach the page', () {
      expect(TurnstilePage.isValidSiteKey('0x4AAAAAAFw-cJ6ZfU7Jch0V'), isTrue);
      for (final bad in [
        '',
        'short',
        "x'; alert(1);//abcdefgh",
        '</script><script>alert(1)</script>',
        'a b c d e f g h i j',
        'a' * 65,
        '0x4AAAA\nAAAAAAAAAAA',
      ]) {
        expect(TurnstilePage.isValidSiteKey(bad), isFalse, reason: bad);
        expect(() => TurnstilePage.html(bad), throwsArgumentError);
      }
    });

    test('the page carries the key and loads only Cloudflare', () {
      final html = TurnstilePage.html('0x4AAAAAAFw-cJ6ZfU7Jch0V');
      expect(html, contains("sitekey: '0x4AAAAAAFw-cJ6ZfU7Jch0V'"));
      expect(
        html,
        contains('https://challenges.cloudflare.com/turnstile/v0/api.js'),
      );
      expect(html, contains('AzmTurnstile.postMessage'));
      final hosts = RegExp('https?://([^/"\']+)')
          .allMatches(html)
          .map((m) => m.group(1))
          .toSet();
      expect(hosts, {'challenges.cloudflare.com'});
    });
  });

  group('navigation', () {
    test('only Cloudflare over https, and the blank page', () {
      expect(TurnstilePage.allowsNavigation('about:blank'), isTrue);
      expect(
        TurnstilePage.allowsNavigation(
          'https://challenges.cloudflare.com/cdn-cgi/challenge-platform/h/b',
        ),
        isTrue,
      );
      for (final url in [
        'http://challenges.cloudflare.com/x',
        'https://evil.example/x',
        'https://challenges.cloudflare.com.evil.example/x',
        'https://user@challenges.cloudflare.com@evil.example/',
        'javascript:alert(1)',
        'file:///etc/passwd',
        'azm://join/K7M2QX',
        'intent://x#Intent;end',
        '',
        'not a url',
      ]) {
        expect(TurnstilePage.allowsNavigation(url), isFalse, reason: url);
      }
    });

    test('the page it is loaded as, and nothing else on that host', () {
      const base = 'https://azmm.pages.dev';
      for (final url in ['https://azmm.pages.dev/', 'https://azmm.pages.dev']) {
        expect(
          TurnstilePage.allowsNavigation(url, baseUrl: base),
          isTrue,
          reason: url,
        );
      }
      for (final url in [
        'https://azmm.pages.dev/privacy',
        'https://azmm.pages.dev/?x=1',
        'https://azmm.pages.dev/#x',
        'http://azmm.pages.dev/',
        'https://azmm.pages.dev:8443/',
        'https://user@azmm.pages.dev/',
        'https://azmm.pages.dev.evil.example/',
        'https://evil.example/',
      ]) {
        expect(
          TurnstilePage.allowsNavigation(url, baseUrl: base),
          isFalse,
          reason: url,
        );
      }
      // Without a base page, the base host stays blocked.
      expect(
        TurnstilePage.allowsNavigation('https://azmm.pages.dev/'),
        isFalse,
      );
    });
  });

  group('messages from the page', () {
    String msg(Object? k, Object? v) => jsonEncode({'k': k, 'v': v});

    test('a token, a failure, a timeout', () {
      final ok = TurnstilePage.parse(msg('token', 'fake-token-for-tests'));
      expect(ok?.value, 'fake-token-for-tests');
      expect(TurnstilePage.parse(msg('error', '110200'))?.failed, isTrue);
      expect(TurnstilePage.parse(msg('timeout', ''))?.timedOut, isTrue);
      expect(TurnstilePage.parse(msg('expired', ''))?.timedOut, isTrue);
    });

    test('anything else is ignored', () {
      for (final raw in [
        '',
        'not json',
        '[]',
        '{}',
        msg('token', ''),
        msg('token', 'short'),
        msg('token', 'has spaces in it ok'),
        msg('token', '<script>alert(1)</script>'),
        msg('token', 'a' * 3000),
        msg('other', 'x'),
        msg(1, 'x'),
        msg('token', 5),
        jsonEncode({'k': 'token', 'v': 'abcdefghijklm', 'extra': 1}),
        'x' * 5000,
      ]) {
        expect(
          TurnstilePage.parse(raw),
          isNull,
          reason: raw.length > 60 ? raw.substring(0, 60) : raw,
        );
      }
    });
  });
}
