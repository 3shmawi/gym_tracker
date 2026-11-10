import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The captain web dashboard (dashboard/, docs/features/dashboard.md) is a
/// separate site on its own origin. These checks pin the rules that keep it
/// from weakening the website or leaking anything:
/// - the website's CSP stays `connect-src 'none'`;
/// - the dashboard's CSP is generated from the Supabase URL and allows only
///   that project, with no inline script or style;
/// - only publishable values are configured; env files stay out of git;
/// - only supabase-js keeps the session; no other browser storage of data;
/// - no invisible direction characters in the dashboard's source
///   ("Trojan Source", CVE-2021-42574).
/// The built files are checked in CI by dashboard/scripts/check_dist.mjs.
void main() {
  String read(String path) => File(path).readAsStringSync();

  Iterable<File> sources(String dir) sync* {
    for (final e in Directory(dir).listSync(recursive: true)) {
      if (e is! File) continue;
      if (e.uri.pathSegments.any({'node_modules', 'dist'}.contains)) continue;
      if (RegExp(r'\.(ts|tsx|mjs|js|css|html)$').hasMatch(e.path)) yield e;
    }
  }

  test("the website's CSP still blocks every connection", () {
    final headers = read('website/_headers');
    expect(headers, contains("connect-src 'none'"));
    expect(headers, isNot(contains('supabase.co')));
  });

  test('the dashboard CSP is strict and names only our Supabase project', () {
    final headers = read('dashboard/build/headers.ts');
    for (final rule in [
      "default-src 'self'",
      "script-src 'self'",
      "style-src 'self'",
      "object-src 'none'",
      "base-uri 'none'",
      "frame-ancestors 'none'",
      r"connect-src 'self' ${supabaseUrl} ${ws}",
      'Strict-Transport-Security: max-age=31536000',
      '! Access-Control-Allow-Origin',
    ]) {
      expect(headers, contains(rule), reason: rule);
    }
    expect(headers, isNot(contains('unsafe-inline')));
    expect(headers, isNot(contains('unsafe-eval')));
    expect(headers, isNot(contains('data:')));
    // D2 pictures: one Cloudinary upload path in img-src, never the host.
    expect(
      headers,
      contains(r'https://res.cloudinary.com/${cloudName}/image/upload/'),
    );
    expect(headers, contains(r"`img-src 'self'${pictures}`"));
    // The build writes _headers and refuses to start without valid config.
    final vite = read('dashboard/vite.config.ts');
    expect(vite, contains("fileName: '_headers'"));
    expect(vite, contains('parseConfig('));
    expect(vite, contains('polyfill: false'));
    expect(vite, contains('assetsInlineLimit: 0'));
  });

  test('only publishable values configure the dashboard', () {
    final config = read('dashboard/src/core/config.ts');
    expect(config, contains('sb_publishable_'));
    expect(config, contains("startsWith('sb_secret_')"));
    final example = read('dashboard/.env.example');
    final keys = RegExp(
      '^([A-Z_]+)=',
      multiLine: true,
    ).allMatches(example).map((m) => m.group(1)).toSet();
    expect(keys, {
      'VITE_SUPABASE_URL',
      'VITE_SUPABASE_PUBLISHABLE_KEY',
      'VITE_TURNSTILE_SITE_KEY',
      'VITE_CLOUDINARY_CLOUD_NAME',
    });
    expect(example, contains('sb_publishable_example_not_a_real_key'));
    final ignore = read('dashboard/.gitignore');
    for (final entry in ['.env', '.env.*', 'node_modules/', 'dist/']) {
      expect(ignore, contains(entry), reason: '$entry must be ignored');
    }
  });

  test('sign-in never creates users, never reads a session from the URL', () {
    final auth = read('dashboard/src/auth/auth.ts');
    expect(auth, contains('shouldCreateUser: false'));
    expect(auth, contains("type: 'email'"));
    final client = read('dashboard/src/core/supabase.ts');
    expect(client, contains('detectSessionInUrl: false'));
  });

  test('only core/prefs.ts touches browser storage, and no HTML injection', () {
    for (final file in sources('dashboard/src')) {
      final text = file.readAsStringSync();
      final path = file.path.replaceAll(r'\', '/');
      if (!path.endsWith('src/core/prefs.ts')) {
        expect(text, isNot(contains('localStorage')), reason: path);
        expect(text, isNot(contains('sessionStorage')), reason: path);
      }
      expect(text, isNot(contains('dangerouslySetInnerHTML')), reason: path);
      expect(text, isNot(contains('innerHTML')), reason: path);
      expect(text, isNot(contains('eval(')), reason: path);
    }
  });

  test('no invisible direction characters in the dashboard source', () {
    final hidden = RegExp(
      '[\u061C\u200B-\u200F\u202A-\u202E\u2060\u2066-\u2069\uFEFF]',
    );
    for (final dir in [
      'dashboard/src',
      'dashboard/test',
      'dashboard/build',
      'dashboard/e2e',
    ]) {
      if (!Directory(dir).existsSync()) continue;
      for (final file in sources(dir)) {
        expect(
          hidden.hasMatch(file.readAsStringSync()),
          isFalse,
          reason: '${file.path} has an invisible direction character',
        );
      }
    }
  });

  test('the dashboard never shares the website origin', () {
    final website = Directory('website')
        .listSync(recursive: true)
        .whereType<File>()
        .map((f) => f.path.replaceAll(r'\', '/'));
    expect(website.where((p) => p.contains('dashboard')), isEmpty);
  });
}
