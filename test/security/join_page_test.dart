import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// website/join.html is shown when a phone scans an invite QR and the app is
/// not installed. Its address carries a one-time code, so the page may only
/// DISPLAY it (textContent), never run it, store it or send it anywhere.
void main() {
  final html = File('website/join.html').readAsStringSync();
  final scripts = {
    for (final name in ['join.js', 'join-code.js'])
      name: File('website/assets/$name').readAsStringSync(),
  };

  test('the code is never put into the page as HTML or run as code', () {
    // The page and its scripts: no way to turn text from the address into
    // markup or script.
    final forbidden = RegExp(
      r'innerHTML|outerHTML|insertAdjacentHTML|document\.write(ln)?\s*\(|'
      r'\beval\s*\(|new\s+Function\s*\(|setTimeout\s*\(\s*["'
      "'"
      '`]|'
      r'setInterval\s*\(\s*["'
      "'"
      '`]|createContextualFragment|srcdoc|'
      r'location\s*(\.href)?\s*=[^=]|location\.(assign|replace)\s*\(|'
      r'window\.open\s*\(',
    );
    for (final MapEntry(:key, :value) in scripts.entries) {
      expect(
        forbidden.hasMatch(value),
        isFalse,
        reason: '$key must not build markup, run strings or navigate',
      );
    }
    expect(forbidden.hasMatch(html), isFalse);
  });

  test('the code is written with textContent, after the format check', () {
    final js = scripts['join.js']!;
    expect(js, contains('codeEl.textContent = code'));
    expect(js, contains('codeFromPath(location.pathname)'));
    // Only the path is read: no query, hash or referrer feeds the page.
    expect(
      RegExp(
        r'location\.(search|hash|href)|document\.(referrer|cookie|URL)|'
        'URLSearchParams',
      ).hasMatch(js),
      isFalse,
    );
    final logic = scripts['join-code.js']!;
    expect(logic, contains('A-HJKMNP-Z2-9'));
    expect(logic, contains('toUpperCase')); // after the ASCII-only check
  });

  test('no inline script, style or event handler (the CSP forbids them)', () {
    expect(RegExp(r'<script(?![^>]*\bsrc=)[^>]*>').hasMatch(html), isFalse);
    expect(RegExp('<style[ >]').hasMatch(html), isFalse);
    expect(RegExp(r'\sstyle\s*=').hasMatch(html), isFalse);
    expect(RegExp(r'\son[a-z]+\s*=').hasMatch(html), isFalse);
    expect(html, isNot(contains('javascript:')));
  });

  test('no trackers, no third parties: only our files and the two stores', () {
    final urls = RegExp(r'''(?:src|href)\s*=\s*"([^"]+)"''')
        .allMatches(html)
        .map((m) => m.group(1)!)
        .toList();
    expect(urls, isNotEmpty);
    for (final url in urls) {
      final ok =
          url.startsWith('/assets/') ||
          url == 'azm://join' ||
          url.startsWith('https://apps.apple.com/') ||
          url.startsWith('https://play.google.com/');
      expect(ok, isTrue, reason: 'unexpected link on the join page: $url');
    }
    for (final MapEntry(:key, :value) in {
      'join.html': html,
      ...scripts,
    }.entries) {
      expect(
        RegExp(
          'analytics|gtag|google-tag|googletagmanager|posthog|sentry|'
          r'facebook|fbq\(|hotjar|cdn\.segment|mixpanel|amplitude|fonts\.g|'
          r'\bfetch\s*\(|XMLHttpRequest|sendBeacon|WebSocket|localStorage\.setItem\([^)]*code',
          caseSensitive: false,
        ).hasMatch(value),
        isFalse,
        reason: '$key must not track or call out',
      );
    }
    // External links never leak the address (which holds the code).
    for (final m in RegExp(
      '<a [^>]*href="https://[^"]+"[^>]*>',
    ).allMatches(html)) {
      expect(m.group(0), contains('rel="noopener noreferrer"'));
    }
    expect(html, contains('name="referrer" content="no-referrer"'));
    expect(html, contains('name="robots" content="noindex, nofollow"'));
  });

  test('the store buttons are the same links as the home page', () {
    final home = File('website/index.html').readAsStringSync();
    for (final host in [
      'https://apps.apple.com/app/',
      'https://play.google.com/store/',
    ]) {
      String? find(String text) =>
          RegExp('$host[^"]+').firstMatch(text)?.group(0);
      expect(find(html), isNotNull);
      expect(find(html), find(home), reason: 'update both pages together');
    }
  });

  test(
    'it works without JavaScript for the buttons and shows both languages',
    () {
      // Plain links, present in the markup (not created by script).
      expect(html, contains('id="open" href="azm://join"'));
      expect(html, contains('id="store-ios" href="https://apps.apple.com/'));
      expect(
        html,
        contains('id="store-android" href="https://play.google.com/'),
      );
      expect(
        html,
        contains(
          '<noscript><link rel="stylesheet" href="/assets/join-nojs.css">',
        ),
      );
      expect(
        File('website/assets/join-nojs.css').readAsStringSync(),
        contains('[data-lang]'),
      );
      // Every English text has its Arabic twin.
      final en = RegExp('data-lang="en"').allMatches(html).length;
      final ar = RegExp('data-lang="ar"').allMatches(html).length;
      expect(en, ar);
      expect(en, greaterThan(8));
    },
  );

  test('Pages serves /join/<code> with this page and never caches it', () {
    final redirects = File('website/_redirects').readAsStringSync();
    expect(
      redirects,
      matches(RegExp(r'^/join/\*\s+/join\.html\s+200$', multiLine: true)),
    );
    final headers = File('website/_headers').readAsStringSync();
    for (final path in ['/join', '/join/*']) {
      final block = RegExp(
        '^${RegExp.escape(path)}\\n((?:  .+\\n?)+)',
        multiLine: true,
      ).firstMatch(headers);
      expect(block, isNotNull, reason: '_headers needs a rule for $path');
      expect(block!.group(1), contains('Cache-Control: no-store'));
      expect(block.group(1), contains('noindex'));
    }
  });

  test('the link shape is the path form, never ?c=', () {
    final all = [html, ...scripts.values].join('\n');
    expect(all, isNot(contains('?c=')));
    expect(all, isNot(contains('join?')));
  });
}
