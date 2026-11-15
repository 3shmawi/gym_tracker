import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether the app runs on a Google test device: Firebase Test Lab, which
/// also powers Google Play's pre-launch report. Those devices are emulators
/// (x86_64, often without a real GPU) that start every new release, crash
/// on the glass shaders, and made up nearly every Sentry crash and error
/// (docs/performance.md → "Google's test devices").
///
/// Detected the documented way: the system setting `firebase.test.lab` is
/// "true" (firebase.google.com/docs/test-lab/android/android-studio, read
/// 2026-11-15). Android only; false everywhere else, and on any failure.
abstract final class TestDevice {
  static const channel = MethodChannel('azm/device');

  static bool _isTestLab = false;

  static bool get isTestLab => _isTestLab;

  /// Tests set the answer here instead of asking the platform.
  @visibleForTesting
  static set isTestLab(bool value) => _isTestLab = value;

  /// Reads the setting once, at start, before monitoring and analytics.
  static Future<void> detect() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      _isTestLab = await channel.invokeMethod<bool>('isTestLab') ?? false;
    } on Object {
      _isTestLab = false;
    }
  }
}
