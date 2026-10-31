import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

/// Remote feature flags (PostHog). Turn features on/off, or roll them out to
/// a percentage of users, from the PostHog dashboard — no release needed.
///
/// Keep flag names in [Flags] so they're easy to find and remove later.
abstract final class FeatureFlags {
  static Future<bool> isEnabled(String flag) async {
    if (!Analytics.isEnabled) return false;
    return await Posthog().isFeatureEnabled(flag);
  }

  static Future<void> reload() async {
    if (!Analytics.isEnabled) return;
    await Posthog().reloadFeatureFlags();
  }
}

/// All feature flag keys used by the app.
abstract final class Flags {
  static const example = 'example_flag';
}
