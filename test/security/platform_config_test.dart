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

    test('the azm:// scheme and only azmm.pages.dev/join/ open the app', () {
      expect(manifest, isNot(contains('gymtracker')));
      expect(manifest, contains('<data android:scheme="azm"/>'));
      // Exactly one https filter: verified, one host, one path prefix.
      final https = RegExp('<data[^>]*android:scheme="https"[^>]*/>')
          .allMatches(manifest)
          .map((m) => m.group(0)!)
          .toList();
      expect(https, hasLength(1));
      expect(https.single, contains('android:host="azmm.pages.dev"'));
      expect(https.single, contains('android:pathPrefix="/join/"'));
      expect(https.single, isNot(contains('pathPattern')));
      expect(manifest, isNot(contains('android:scheme="http"')));
      expect(
        RegExp(
          '<intent-filter android:autoVerify="true">(?:(?!</intent-filter>)'
          '.)*android:scheme="https"',
          dotAll: true,
        ).hasMatch(manifest),
        isTrue,
        reason: 'the https filter needs android:autoVerify="true"',
      );
    });

    test('only the launcher activity is exported', () {
      final exported = RegExp('android:exported="true"').allMatches(manifest);
      expect(exported.length, 1);
    });

    // "Rest over" (flutter_local_notifications): least privilege.
    test('rest notification: exact alarms the user grants, nothing more', () {
      expect(manifest, contains('android.permission.SCHEDULE_EXACT_ALARM'));
      // Google Play only allows USE_EXACT_ALARM for alarm-clock and
      // calendar apps; full-screen intents and boot receivers aren't needed.
      for (final p in [
        'USE_EXACT_ALARM',
        'USE_FULL_SCREEN_INTENT',
        'RECEIVE_BOOT_COMPLETED',
      ]) {
        expect(manifest, isNot(contains('permission.$p"')), reason: p);
      }
      expect(
        RegExp(
          r'<receiver android:exported="false" android:name="com\.dexterous'
          r'\.flutterlocalnotifications\.ScheduledNotificationReceiver"',
        ).hasMatch(manifest),
        isTrue,
      );
    });

    test('the notification icon survives R8 in release builds', () {
      final keep = File('android/app/src/main/res/raw/keep.xml')
          .readAsStringSync();
      expect(keep, contains('@drawable/ic_stat_rest'));
      for (final dpi in ['mdpi', 'hdpi', 'xhdpi', 'xxhdpi', 'xxxhdpi']) {
        expect(
          File('android/app/src/main/res/drawable-$dpi/ic_stat_rest.png')
              .existsSync(),
          isTrue,
          reason: dpi,
        );
      }
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

<<<<<<< yours
    // The kit adds these at creation; its patch once failed silently on
=======
    // new_project.sh adds these; its patch once failed silently on
>>>>>>> kit 1928c02
    // flavorizr's indented Info.plist, so they are checked here.
    bool has(String key, String value) =>
        RegExp('<key>${RegExp.escape(key)}</key>\\s*${RegExp.escape(value)}')
            .hasMatch(plist);

    test('declares exempt encryption (no export question per build)', () {
<<<<<<< yours
      // Only HTTPS/TLS: exempt. App Store Connect then skips "App
      // Encryption Documentation" for every build, staging and prod.
      expect(has('ITSAppUsesNonExemptEncryption', '<false/>'), isTrue);
    });

    test('the azm:// scheme opens the app (deep links)', () {
      expect(has('FlutterDeepLinkingEnabled', '<true/>'), isTrue);
      expect(plist, contains('<string>azm</string>'));
      expect(plist, isNot(contains('gymtracker')));
    });

    test('Universal Links: only applinks:azmm.pages.dev, in every flavor', () {
      final entitlements = File('ios/Runner/Runner.entitlements')
          .readAsStringSync();
      final domains = RegExp('<string>([^<]*)</string>')
          .allMatches(entitlements)
          .map((m) => m.group(1))
          .toList();
      expect(domains, ['applinks:azmm.pages.dev']);

      // Every Runner build configuration (Debug/Release/Profile x staging/
      // prod) signs with the entitlements; RunnerTests has no Info.plist.
      final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      final configs = 'INFOPLIST_FILE = Runner/Info.plist;'.allMatches(pbxproj);
      final signed = 'CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;'
          .allMatches(pbxproj);
      expect(configs.length, greaterThanOrEqualTo(6));
      expect(signed.length, configs.length);
=======
      expect(has('ITSAppUsesNonExemptEncryption', '<false/>'), isTrue);
    });

    test('the custom scheme opens the app (deep links)', () {
      expect(has('FlutterDeepLinkingEnabled', '<true/>'), isTrue);
      expect(plist, contains('<string>gymtracker</string>'));
>>>>>>> kit 1928c02
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
<<<<<<< yours

    test('notification taps reach the app (delegate set)', () {
      final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      expect(delegate, contains('UNUserNotificationCenter.current().delegate'));
    });

    test('PostHog starts from Dart only, not by itself', () {
      expect(has('com.posthog.posthog.AUTO_INIT', '<false/>'), isTrue);
    });
=======
>>>>>>> kit 1928c02
  });
}
