import 'dart:async';

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
    final problem = configProblem(Env.posthogApiKey, Env.posthogHost);
    if (problem != null) {
      // Says why the dashboard stays empty; never prints the key itself.
      debugPrint('Analytics off: $problem');
      return;
    }
    final config = PostHogConfig(Env.posthogApiKey)
      ..host = Env.posthogHost
      ..captureApplicationLifecycleEvents = true
      ..debug = !AppFlavor.current.isProd;
    await Posthog().setup(config);
    _enabled = true;
    await _tag(tagsFor(AppFlavor.current));
  }

  /// This app's name in PostHog. One PostHog project can hold every app:
  /// the [tagsFor] properties keep their data apart.
  static const appName = 'gym_tracker';

  /// Sent with every event (`app`, `environment`) and set on the person, so
  /// insights, cohorts and feature flags can filter by app and environment
  /// (e.g. a flag released only where app = gym_tracker
  /// and environment = prod).
  @visibleForTesting
  static Map<String, String> tagsFor(AppFlavor flavor) => {
    'app': appName,
    'environment': flavor.name,
  };

  static Future<void> _tag(Map<String, String> tags) async {
    final posthog = Posthog();
    for (final MapEntry(:key, :value) in tags.entries) {
      await posthog.register(key, value);
    }
    await posthog.setPersonProperties(userPropertiesToSet: tags);
    // Flags are evaluated with these at once (no wait for the person
    // update); the reload runs in the background, start-up doesn't wait.
    unawaited(posthog.setPersonPropertiesForFlags(tags));
  }

  /// Why PostHog can't receive events with this [apiKey] and [host], or
  /// null when they look right. A personal key (phx_) or the dashboard
  /// address as host is accepted by the SDK, but every event is dropped.
  @visibleForTesting
  static String? configProblem(String apiKey, String host) {
    if (apiKey.isEmpty) return 'POSTHOG_API_KEY is empty in env/<name>.json';
    if (!apiKey.startsWith('phc_')) {
      return 'POSTHOG_API_KEY is not a project API key (starts with phc_)';
    }
    if (!host.startsWith('https://')) {
      return 'POSTHOG_HOST must start with https://';
    }
    if (RegExp(r'^https://(eu|us|app)\.posthog\.com/?$').hasMatch(host)) {
      return 'POSTHOG_HOST is the dashboard address; use '
          'https://eu.i.posthog.com or https://us.i.posthog.com';
    }
    return null;
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
    // reset() also clears the app/environment tags.
    await _tag(tagsFor(AppFlavor.current));
  }

  /// Records screen views automatically.
  static List<NavigatorObserver> get navigatorObservers =>
      _enabled ? [PosthogObserver()] : const [];
}
