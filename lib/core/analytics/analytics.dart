import 'package:flutter/widgets.dart';
import 'package:gym_tracker/core/config/app_flavor.dart';
import 'package:gym_tracker/core/config/env.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

/// Product analytics (PostHog). Every call is a no-op until
/// `POSTHOG_API_KEY` is set in the env file.
///
/// Event names: snake_case, `<object>_<verb>` — e.g. `menu_item_viewed`.
abstract final class Analytics {
  static bool _enabled = false;

  static bool get isEnabled => _enabled;

  static Future<void> init() async {
    if (Env.posthogApiKey.isEmpty) return;
    final config = PostHogConfig(Env.posthogApiKey)
      ..host = Env.posthogHost
      ..captureApplicationLifecycleEvents = true
      ..debug = !AppFlavor.current.isProd;
    await Posthog().setup(config);
    _enabled = true;
  }

  static Future<void> capture(
    String event, [
    Map<String, Object>? properties,
  ]) async {
    if (!_enabled) return;
    await Posthog().capture(eventName: event, properties: properties);
  }

  static Future<void> identify(String userId) async {
    if (!_enabled) return;
    await Posthog().identify(userId: userId);
  }

  static Future<void> reset() async {
    if (!_enabled) return;
    await Posthog().reset();
  }

  /// Records screen views automatically.
  static List<NavigatorObserver> get navigatorObservers =>
      _enabled ? [PosthogObserver()] : const [];
}
