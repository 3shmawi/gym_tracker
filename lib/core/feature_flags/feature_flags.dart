import 'package:flutter/foundation.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

/// Remote feature flags (PostHog). Turn features on/off, or roll them out to
/// a percentage of users, from the PostHog dashboard — no release needed.
///
/// Keep flag names in [Flags] so they're easy to find and remove later.
abstract final class FeatureFlags {
  /// Tests set a flag here instead of asking PostHog.
  @visibleForTesting
  static final Map<String, bool> overrides = {};

  static Future<bool> isEnabled(String flag) async {
    final override = overrides[flag];
    if (override != null) return override;
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

  /// `/join` and `/join/<code>` open the enter-code screen. Off: they open
  /// the home screen, as before gym accounts. Turn on in PostHog once
  /// joining works (docs/decisions/gym_accounts.md §13, step 3).
  static const gymJoin = 'gym_join';
}
