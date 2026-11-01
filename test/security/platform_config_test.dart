import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Native configuration that must stay secure in every release.
void main() {
  group('Android', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    test('does not allow cleartext (http) traffic', () {
      expect(manifest, isNot(contains('usesCleartextTraffic="true"')));
    });

    test('release builds are not debuggable', () {
      expect(manifest, isNot(contains('android:debuggable="true"')));
    });

    test('only the launcher activity is exported', () {
      final exported = RegExp('android:exported="true"').allMatches(manifest);
      expect(exported.length, 1);
    });
  });

  group('iOS', () {
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    test('App Transport Security is not disabled', () {
      final arbitraryLoads = RegExp(
        r'<key>NSAllowsArbitraryLoads</key>\s*<true/>',
      );
      expect(arbitraryLoads.hasMatch(plist), isFalse);
    });

    // The kit adds these at creation; its patch once failed silently on
    // flavorizr's indented Info.plist, so they are checked here.
    bool has(String key, String value) =>
        RegExp('<key>${RegExp.escape(key)}</key>\\s*${RegExp.escape(value)}')
            .hasMatch(plist);

    test('declares exempt encryption (no export question per build)', () {
      // Only HTTPS/TLS: exempt. App Store Connect then skips "App
      // Encryption Documentation" for every build, staging and prod.
      expect(has('ITSAppUsesNonExemptEncryption', '<false/>'), isTrue);
    });

    test('the gymtracker:// scheme opens the app (deep links)', () {
      expect(has('FlutterDeepLinkingEnabled', '<true/>'), isTrue);
      expect(plist, contains('<string>gymtracker</string>'));
    });

    test('declares English and Arabic', () {
      expect(
        RegExp(
          r'<key>CFBundleLocalizations</key>\s*<array>\s*<string>en</string>'
          r'\s*<string>ar</string>',
        ).hasMatch(plist),
        isTrue,
      );
    });

    test('PostHog starts from Dart only, not by itself', () {
      expect(has('com.posthog.posthog.AUTO_INIT', '<false/>'), isTrue);
    });
  });
}
