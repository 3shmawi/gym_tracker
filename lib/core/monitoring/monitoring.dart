import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:gym_tracker/core/config/app_flavor.dart';
import 'package:gym_tracker/core/config/env.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Crash, error and performance monitoring — backed by Sentry.
///
/// The rest of the app only talks to [Monitoring], so switching or adding a
/// provider means changing this one file. Disabled until `SENTRY_DSN` is set.
abstract final class Monitoring {
  static bool get _enabled => Env.sentryDsn.isNotEmpty;

  /// Starts Flutter with Sentry's binding. Call it instead of
  /// `WidgetsFlutterBinding.ensureInitialized()`: with the plain binding
  /// Sentry's frame tracking turns itself off ("incompatible binding"), and
  /// no slow or frozen frames reach Sentry. When a binding already exists
  /// (tests) it is kept.
  static WidgetsBinding ensureBinding() =>
      SentryWidgetsFlutterBinding.ensureInitialized();

  /// Builds the app inside Sentry's zone so start-up errors are captured.
  static Future<void> run(Future<Widget> Function() appBuilder) async {
    if (!_enabled) {
      runApp(await appBuilder());
      return;
    }
    await SentryFlutter.init((options) {
      options
        ..dsn = Env.sentryDsn
        ..environment = AppFlavor.current.name
        ..tracesSampleRate = AppFlavor.current.isProd ? 0.2 : 1.0
        ..sendDefaultPii = false;
    }, appRunner: () async => runApp(SentryWidget(child: await appBuilder())));
  }

  /// Reports an error you caught and handled.
  static Future<void> captureException(
    Object error, [
    StackTrace? stackTrace,
  ]) async {
    if (!_enabled) {
      debugPrint('Monitoring: $error\n$stackTrace');
      return;
    }
    await Sentry.captureException(error, stackTrace: stackTrace);
  }

  /// Ties errors to the signed-in user (call with `null` on sign-out).
  static Future<void> setUser(String? id) async {
    if (!_enabled) return;
    await Sentry.configureScope(
      (scope) => scope.setUser(id == null ? null : SentryUser(id: id)),
    );
  }

  static List<NavigatorObserver> get navigatorObservers =>
      _enabled ? [SentryNavigatorObserver()] : const [];
}
