import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The website is served from https://azmm.pages.dev (Cloudflare Pages).
/// Its `.well-known` files decide which links open the app, so they are
/// checked like code: public ids only, one path, one host.
void main() {
  const host = 'azmm.pages.dev';
  // Assembled so this file does not itself contain the retired host.
  final oldHost = ['3shmawi', 'github', 'io'].join('.');

  final aasa = jsonDecode(
    File('website/.well-known/apple-app-site-association').readAsStringSync(),
  ) as Map<String, dynamic>;
  final assetLinks = jsonDecode(
    File('website/.well-known/assetlinks.json').readAsStringSync(),
  ) as List<dynamic>;

  group('apple-app-site-association', () {
    test('only the applinks section, only the /join/* path', () {
      expect(aasa.keys, ['applinks']);
      final applinks = aasa['applinks'] as Map<String, dynamic>;
      expect(applinks.keys.toSet(), {'details'});
      final details = applinks['details'] as List<dynamic>;
      expect(details, hasLength(1));
      final detail = details.single as Map<String, dynamic>;
      expect(detail.keys.toSet(), {'appIDs', 'components'});
      final components = (detail['components'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(components, hasLength(1));
      expect(components.single['/'], '/join/*');
      expect(components.single['exclude'], isNull);
    });

    test('app ids are <team id>.<bundle id> for prod and staging', () {
      final detail =
          ((aasa['applinks'] as Map<String, dynamic>)['details']
                      as List<dynamic>)
                  .single
              as Map<String, dynamic>;
      expect(detail['appIDs'], [
        '9RA43G2P63.com.mohager.azm',
        '9RA43G2P63.com.mohager.azm.stg',
      ]);
    });
  });

  group('assetlinks.json', () {
    final fingerprint = RegExp(r'^([0-9A-F]{2}:){31}[0-9A-F]{2}$');
    final placeholder = RegExp(r'^REPLACE_WITH_[A-Z_]*SHA256$');

    test('only our two Android packages, only handle_all_urls', () {
      final packages = <String>[];
      for (final entry in assetLinks.cast<Map<String, dynamic>>()) {
        expect(entry.keys.toSet(), {'relation', 'target'});
        expect(entry['relation'], [
          'delegate_permission/common.handle_all_urls',
        ]);
        final target = entry['target'] as Map<String, dynamic>;
        expect(target.keys.toSet(), {
          'namespace',
          'package_name',
          'sha256_cert_fingerprints',
        });
        expect(target['namespace'], 'android_app');
        packages.add(target['package_name'] as String);
      }
      expect(packages, ['com.mohager.azm', 'com.mohager.azm.stg']);
    });

    test(
      'fingerprints are public SHA-256 values or the marked placeholder',
      () {
        for (final entry in assetLinks.cast<Map<String, dynamic>>()) {
          final target = entry['target'] as Map<String, dynamic>;
          final prints = (target['sha256_cert_fingerprints'] as List<dynamic>)
              .cast<String>();
          expect(prints, isNotEmpty);
          for (final p in prints) {
            expect(
              fingerprint.hasMatch(p) || placeholder.hasMatch(p),
              isTrue,
              reason: 'unexpected value in assetlinks.json',
            );
          }
        }
      },
    );
  });

  test('the .well-known files hold no secrets', () {
    final files = Directory('website/.well-known').listSync().whereType<File>();
    expect(files, hasLength(2));
    final secret = RegExp(
      '-----BEGIN|sb_secret_|service_role|eyJ[A-Za-z0-9_-]{20,}'
      '|AKIA[0-9A-Z]{16}'
      '|ghp_[A-Za-z0-9]{20,}|AIza[0-9A-Za-z_-]{20,}|sk_live_|password|token'
      '|api[_-]?key',
      caseSensitive: false,
    );
    for (final file in files) {
      expect(
        secret.hasMatch(file.readAsStringSync()),
        isFalse,
        reason: file.path,
      );
    }
  });

  test('_headers serves both .well-known files as application/json', () {
    final headers = File('website/_headers').readAsStringSync();
    for (final path in [
      '/.well-known/apple-app-site-association',
      '/.well-known/assetlinks.json',
    ]) {
      final block = RegExp(
        '^${RegExp.escape(path)}\\n((?:[ \\t]+.*\\n?)+)',
        multiLine: true,
      ).firstMatch(headers);
      expect(block, isNotNull, reason: path);
      expect(block!.group(1), contains('Content-Type: application/json'));
    }
  });

  test('_headers hardens every page (CSP, no framing, no sniffing)', () {
    final headers = File('website/_headers').readAsStringSync();
    final block = RegExp(
      r'^/\*\n((?:[ \t]+.*\n?)+)',
      multiLine: true,
    ).firstMatch(headers);
    expect(block, isNotNull);
    final rules = block!.group(1)!;
    expect(rules, contains("default-src 'none'"));
    expect(rules, contains("script-src 'self'"));
    expect(rules, contains("frame-ancestors 'none'"));
    // No way to weaken the policy.
    expect(rules, isNot(contains('unsafe-inline')));
    expect(rules, isNot(contains('unsafe-eval')));
    expect(rules, isNot(contains('script-src *')));
    expect(rules, contains('X-Content-Type-Options: nosniff'));
    expect(rules, contains('X-Frame-Options: DENY'));
  });

  test('pages keep no inline script or style (the CSP would block it)', () {
    final inline = RegExp(
      r'<script(?![^>]*\ssrc=)|<style|\sstyle=|\son[a-z]+=',
      caseSensitive: false,
    );
    for (final f in Directory('website').listSync().whereType<File>()) {
      if (f.path.endsWith('.html')) {
        expect(inline.hasMatch(f.readAsStringSync()), isFalse, reason: f.path);
      }
    }
  });

  test('no GitHub Pages deploy is left', () {
    expect(File('.github/workflows/website.yml').existsSync(), isFalse);
  });

  group('links point to $host', () {
    final linkPattern = RegExp(r'''https?://[^\s"'<>)`]+''');

    Iterable<File> files(String dir, {Set<String>? ext}) => Directory(dir)
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (f) =>
              !f.path.contains('/.') ||
              f.path.contains('.well-known') ||
              f.path.endsWith('_headers'),
        )
        .where((f) => ext == null || ext.any(f.path.endsWith));

    test(
      'website pages link only to the project site or external services',
      () {
        // External hosts the pages may use (fonts, mail, stores, our backend).
        const allowed = {
          'azmm.pages.dev',
          'fonts.googleapis.com',
          'fonts.gstatic.com',
          'play.google.com',
          'apps.apple.com',
          'www.w3.org',
          'supabase.com',
          'posthog.com',
          'sentry.io',
          'policies.google.com',
          'www.apple.com',
        };
        for (final file in files('website', ext: {'.html', '.js', '.css'})) {
          for (final m in linkPattern.allMatches(file.readAsStringSync())) {
            final uri = Uri.parse(m.group(0)!);
            expect(uri.host, isNot(contains('github.io')), reason: file.path);
            expect(uri.scheme, 'https', reason: '${file.path}: $uri');
            expect(
              allowed.any((h) => uri.host == h || uri.host.endsWith('.$h')),
              isTrue,
              reason: '${file.path} links to ${uri.host}',
            );
          }
        }
      },
    );

    test('store texts, app, docs and config use $host, never $oldHost', () {
      final roots = [
        'store',
        'lib',
        'docs',
        'android',
        'ios/Runner',
        '.github',
        'website',
        'scripts',
      ];
      final singles = ['CLAUDE.md', 'README.md', '.project-kit.env'];
      for (final f in [
        for (final r in roots) ...files(r),
        for (final s in singles) File(s),
      ]) {
        if (!f.path.endsWith('.png') && !f.path.endsWith('.jar')) {
          final text = _readOrEmpty(f);
          expect(text, isNot(contains(oldHost)), reason: f.path);
        }
      }
    });

    test('store listings link the privacy policy and support on $host', () {
      const policy = 'https://$host/privacy';
      for (final f in [
        'store/ios/en-US/privacy_url.txt',
        'store/ios/ar-SA/privacy_url.txt',
      ]) {
        expect(File(f).readAsStringSync().trim(), policy, reason: f);
      }
      for (final f in [
        'store/ios/en-US/support_url.txt',
        'store/ios/ar-SA/support_url.txt',
        'store/ios/en-US/marketing_url.txt',
        'store/ios/ar-SA/marketing_url.txt',
      ]) {
        expect(File(f).readAsStringSync().trim(), 'https://$host', reason: f);
      }
      for (final f in [
        'store/android/en-US/full_description.txt',
        'store/android/ar/full_description.txt',
        'store/ios/en-US/description.txt',
        'store/ios/ar-SA/description.txt',
      ]) {
        expect(File(f).readAsStringSync(), contains(policy), reason: f);
      }
    });

    test('the kit env and CLAUDE.md name the same domain', () {
      expect(
        File('.project-kit.env').readAsStringSync(),
        contains('DEEPLINK_DOMAIN=$host'),
      );
      final claude = File('CLAUDE.md').readAsStringSync();
      expect(claude, contains('https://$host'));
      expect(claude, isNot(contains('example.com')));
      expect(claude, isNot(contains('gymtracker://')));
    });
  });
}

String _readOrEmpty(File f) {
  try {
    return f.readAsStringSync();
  } on FileSystemException {
    return '';
  }
}
