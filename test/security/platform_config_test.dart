import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Native configuration that must stay secure in every release.
void main() {
  group('Android', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();

    /// Permissions the app asks for: every <uses-permission> except the
    /// ones that remove a library's permission from the merged manifest.
    final granted = [
      for (final m in RegExp('<uses-permission[^>]*>').allMatches(manifest))
        if (!m.group(0)!.contains('tools:node="remove"')) m.group(0)!,
    ].join('\n');

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

    // The gym QR scanner (docs/decisions/gym_accounts.md §8).
    test('the camera: asked for, but the app installs without one', () {
      expect(manifest, contains('android.permission.CAMERA'));
      expect(
        RegExp(
          r'<uses-feature android:name="android.hardware.camera"\s+'
          r'android:required="false"\s*/>',
        ).hasMatch(manifest),
        isTrue,
        reason: 'required=false: typing the code works without a camera',
      );
    });

    test('no other sensor or storage permission came with the scanner', () {
      for (final p in [
        'RECORD_AUDIO',
        'READ_EXTERNAL_STORAGE',
        'WRITE_EXTERNAL_STORAGE',
        'READ_MEDIA',
        'ACCESS_FINE_LOCATION',
        'ACCESS_COARSE_LOCATION',
        'READ_CONTACTS',
        'USE_BIOMETRIC',
      ]) {
        expect(granted, isNot(contains('permission.$p')), reason: p);
      }
    });

    // Move games (docs/designs/move_games.md §11): the camera plugin and
    // ML Kit bring permissions the app never uses; the app removes them.
    test('Move games: library permissions removed, camera still optional', () {
      for (final p in [
        'RECORD_AUDIO',
        'WRITE_EXTERNAL_STORAGE',
        'READ_EXTERNAL_STORAGE',
        'RECEIVE_BOOT_COMPLETED',
      ]) {
        expect(
          RegExp(
            '<uses-permission android:name="android.permission.$p" '
            'tools:node="remove"/>',
          ).hasMatch(manifest),
          isTrue,
          reason: '$p must be removed from the merged manifest',
        );
      }
      expect(
        manifest,
        contains(
          '<uses-feature android:name="android.hardware.camera.any" '
          'android:required="false" tools:replace="android:required"/>',
        ),
      );
      expect(
        manifest,
        contains('xmlns:tools="http://schemas.android.com/tools"'),
      );
    });

    test("Move games: ML Kit's unused accurate model is not shipped", () {
      final gradle = File('android/app/build.gradle.kts').readAsStringSync();
      expect(
        gradle,
        contains(
          'exclude(group = "com.google.mlkit", module = '
          '"pose-detection-accurate")',
        ),
      );
      final rules = File('android/app/proguard-rules.pro').readAsStringSync();
      expect(
        rules,
        contains('-dontwarn com.google.mlkit.vision.pose.accurate.**'),
      );
    });

    test('Move games: the spoken count only looks for the TTS engine', () {
      // flutter_tts: Android 11+ package visibility for the speech engine.
      // An intent query, not a permission; nothing else is made visible.
      final queries = RegExp(
        '<queries>(.*?)</queries>',
        dotAll: true,
      ).firstMatch(manifest)!.group(1)!;
      final actions = RegExp('android:name="([^"]+)"')
          .allMatches(queries)
          .map((m) => m.group(1))
          .toSet();
      expect(actions, {
        'android.intent.action.PROCESS_TEXT',
        'android.intent.action.TTS_SERVICE',
      });
      expect(manifest, isNot(contains('QUERY_ALL_PACKAGES')));
      expect(granted, isNot(contains('RECORD_AUDIO')));
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
        expect(granted, isNot(contains('permission.$p"')), reason: p);
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
    });

    test('says why the camera is used, in English and Arabic', () {
      // The QR scanner and Move games (docs/designs/move_games.md §11).
      const en =
          "Azm uses the camera to scan your gym's QR code and, in Move "
          'games, to count your reps on your phone. Nothing is recorded, '
          'saved or sent.';
      const ar =
          'يستخدم عزم الكاميرا لقراءة رمز QR الخاص بالجيم، وفي ألعاب '
          'الحركة لعدّ تكراراتك على هاتفك. لا يتم تسجيل أي صور أو '
          'حفظها أو إرسالها.';
      expect(has('NSCameraUsageDescription', '<string>$en</string>'), isTrue);
      final strings = {
        'en': File('ios/Runner/en.lproj/InfoPlist.strings').readAsStringSync(),
        'ar': File('ios/Runner/ar.lproj/InfoPlist.strings').readAsStringSync(),
      };
      expect(strings['en'], contains('"NSCameraUsageDescription" = "$en";'));
      expect(strings['ar'], contains('"NSCameraUsageDescription" = "$ar";'));
      // The files are part of the app: a variant group in the Runner target.
      final pbxproj = File('ios/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();
      expect(pbxproj, contains('path = en.lproj/InfoPlist.strings;'));
      expect(pbxproj, contains('path = ar.lproj/InfoPlist.strings;'));
      expect(pbxproj, contains('InfoPlist.strings in Resources'));
      expect(
        RegExp(r'knownRegions = \([^)]*\bar,').hasMatch(pbxproj),
        isTrue,
        reason: 'Arabic must be a known region or the strings are ignored',
      );
    });

    test('asks for no other private data', () {
      for (final key in [
        'NSPhotoLibraryUsageDescription',
        'NSMicrophoneUsageDescription',
        'NSLocationWhenInUseUsageDescription',
        'NSContactsUsageDescription',
        'NSFaceIDUsageDescription',
        'NSUserTrackingUsageDescription',
      ]) {
        expect(plist, isNot(contains(key)), reason: key);
      }
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

    test('notification taps reach the app (delegate set)', () {
      final delegate = File('ios/Runner/AppDelegate.swift').readAsStringSync();
      expect(delegate, contains('UNUserNotificationCenter.current().delegate'));
    });

    test('PostHog starts from Dart only, not by itself', () {
      expect(has('com.posthog.posthog.AUTO_INIT', '<false/>'), isTrue);
    });

    group('Move games: the ML Kit pose model', () {
      // Google's own files (dl.google.com, MLKitPoseDetection 1.0.0-beta16),
      // the same bytes as google-mlkit-swiftpm 9.0.2's release bundles.
      // scripts/ios_mlkit_bundles.sh fetches and checks them; update both.
      const pins = {
        'MLKitPoseDetectionCommonResources.bundle/pose_non_tracking_graph.binarypb':
            '5258fc9ed2e1598b9739534e2393e012928f441de901451e85e9329b5d763012',
        'MLKitPoseDetectionCommonResources.bundle/pose_tracking_graph.binarypb':
            'e28fe1c1a0b8e1a014e4c4135499a70c50a0f248d834fb21ea0c0339e9e5d8b5',
        'MLKitPoseDetectionFastResources.bundle/pose_landmark_detector_fast.tflite':
            '774adb54eb742c8a7f8fe39b19d0d1ae42cd776015bbdf3e57bde14c5fd8b773',
        'MLKitPoseDetectionFastResources.bundle/pose_person_detector_fast.tflite':
            'a63c614bef30d35947f13be361820b1e4e3bec9cfeebf4d11216a18373108e85',
        'MLKitXenoResources.bundle/yuv_to_rgb_graph.binarypb':
            '943fec320f003427c2181f0712168b00f5b04108672906033013e452d2b1c73e',
      };
      final dir = Directory('ios/Runner/MLKit');
      final project = File('ios/Runner.xcodeproj/project.pbxproj')
          .readAsStringSync();

      test('exactly the pinned model files ship, byte for byte', () async {
        final files = dir
            .listSync(recursive: true)
            .whereType<File>()
            .map((f) => f.path.substring(dir.path.length + 1))
            .toSet();
        expect(files, pins.keys.toSet());
        for (final MapEntry(:key, :value) in pins.entries) {
          final result = await Process.run('sha256sum', ['${dir.path}/$key']);
          if (result.exitCode != 0) {
            // macOS: no sha256sum.
            final mac = await Process.run('shasum', [
              '-a',
              '256',
              '${dir.path}/$key',
            ]);
            expect(mac.stdout.toString(), startsWith(value), reason: key);
          } else {
            expect(result.stdout.toString(), startsWith(value), reason: key);
          }
        }
      });

      test(
        "the accurate model isn't shipped (base model only, as Android)",
        () {
          expect(project, isNot(contains('Accurate')));
          expect(
            Directory(
              'ios/Runner/MLKit/MLKitPoseDetectionAccurateResources.bundle',
            ).existsSync(),
            isFalse,
          );
        },
      );

      test('the three bundles are copied into the app', () {
        final resources = RegExp(
          r'97C146EC1CF9000F007C117D /\* Resources \*/ = \{[^}]*\}',
        ).firstMatch(project)!.group(0)!;
        for (final b in [
          'MLKitPoseDetectionFastResources',
          'MLKitPoseDetectionCommonResources',
          'MLKitXenoResources',
        ]) {
          expect(resources, contains('$b.bundle in Resources'), reason: b);
          expect(project, contains('path = $b.bundle;'), reason: b);
        }
      });

      test('every build configuration links ML Kit with -ObjC -all_load', () {
        expect(
          File('ios/Flutter/MLKit.xcconfig').readAsStringSync(),
          contains(r'OTHER_LDFLAGS = $(inherited) -ObjC -all_load'),
        );
        final configs = RegExp(
          r'baseConfigurationReference = [0-9A-F]+ /\* ([^*]+) \*/',
        ).allMatches(project).map((m) => m.group(1)!.trim()).toSet();
        expect(configs, isNotEmpty);
        for (final name in configs) {
          final file = File('ios/Flutter/${name.replaceFirst('Flutter/', '')}');
          expect(
            file.readAsStringSync(),
            contains('#include "MLKit.xcconfig"'),
            reason: name,
          );
        }
      });
    });
  });
}
