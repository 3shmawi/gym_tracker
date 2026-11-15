import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:gym_tracker/core/config/app_flavor.dart';
import 'package:gym_tracker/core/config/env.dart';
import 'package:gym_tracker/core/device/test_device.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Crash, error and performance monitoring — backed by Sentry.
///
/// The rest of the app only talks to [Monitoring], so switching or adding a
/// provider means changing this one file. Disabled until `SENTRY_DSN` is set.
abstract final class Monitoring {
  /// Off without a DSN, and on Google's test devices: their emulators made
  /// up nearly every crash and error in Sentry (docs/performance.md).
  static bool get _enabled => Env.sentryDsn.isNotEmpty && !TestDevice.isTestLab;

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
        ..sendDefaultPii = false
        // A phone with no network, or a server that is down for a moment,
        // is not a bug: those errors are dropped, also the ones Sentry
        // catches by itself (e.g. the session refresh while offline).
        ..beforeSend = (event, hint) {
          final Object? error = event.throwable;
          return error != null && isOutage(error) ? null : event;
        };
    }, appRunner: () async => runApp(SentryWidget(child: await appBuilder())));
  }

  /// Reports an error you caught and handled. No network, a timeout, or a
  /// server that answered 502/503/504 is not reported: it is not a bug, the
  /// app already shows offline or retries.
  static Future<void> captureException(
    Object error, [
    StackTrace? stackTrace,
  ]) async {
    if (isOutage(error)) return;
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
