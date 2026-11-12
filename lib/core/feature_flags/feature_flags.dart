import 'package:flutter/foundation.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

/// The last answer PostHog gave for a flag, kept on the phone. A flag that
/// changes how the app looks is read from here at start, so the app does
/// not open one way and change a moment later.
abstract interface class FlagCache {
  bool? read(String flag);
  Future<void> write(String flag, {required bool value});
}

/// Until `Dependencies.init`, and in tests.
class InMemoryFlagCache implements FlagCache {
  final Map<String, bool> _values = {};

  @override
  bool? read(String flag) => _values[flag];

  @override
  Future<void> write(String flag, {required bool value}) async =>
      _values[flag] = value;
}

class PrefsFlagCache implements FlagCache {
  const new(this._prefs);

  final SharedPreferences _prefs;

  static String keyFor(String flag) => 'flags.$flag';

  @override
  bool? read(String flag) {
    final value = _prefs.get(keyFor(flag));
    return value is bool ? value : null;
  }

  @override
  Future<void> write(String flag, {required bool value}) =>
      _prefs.setBool(keyFor(flag), value);
}

/// All feature flag keys used by the app.
abstract final class Flags {
  static const example = 'example_flag';

  /// `/join` and `/join/<code>` open the enter-code screen. Off: they open
  /// the home screen, as before gym accounts. Turn on in PostHog once
  /// joining works (docs/decisions/gym_accounts.md §13, step 3).
  static const gymJoin = 'gym_join';

  /// A gym's members see the colour its owner chose while that gym is their
  /// workspace. Off: Azm's colours everywhere, even if a colour is saved
  /// (docs/designs/gym_brand_colours.md → Rollout).
  static const gymBrandColours = 'gym_brand_colours';

  /// The pose check (Settings → About): the camera counts push-ups and
  /// shows the model's speed, to measure phones before Move games ship.
  /// Never in prod builds, whatever the flag says
  /// (docs/designs/move_games.md §9).
  static const moveGamesDebug = 'move_games_debug';
}
