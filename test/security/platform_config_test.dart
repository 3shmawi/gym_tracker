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
  });
}
