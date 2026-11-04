import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/monitoring/monitoring.dart';
import 'package:gym_tracker/features/workout/domain/services/rest_alarm.dart';

/// Override in tests: `restAlarmProvider.overrideWithValue(fake)`.
final restAlarmProvider = Provider<RestAlarm>((ref) => Dependencies.restAlarm);

/// Keeps the "Rest over" notification in step with the workout screen:
/// scheduled only while a rest is running **and** the app is not in front
/// (locked, in the background, app switcher), removed as soon as the
/// member is back, the rest changes (+15 s, skip, a set logged, edited or
/// deleted), the workout is finished or the screen is closed.
///
/// In front, the screen counts down itself, so nothing is scheduled; when
/// the rest runs out on screen (not skipped) it rings right away
/// ([RestAlarm.ringNow]): a vibration alone is easy to miss at the gym
/// (field test 2026-11-03).
class RestAlarmSync {
  new(this._alarm, {required DateTime Function() now}) : _clock = now;

  final RestAlarm _alarm;
  final DateTime Function() _clock;

  bool _inBackground = false;
  RestAlarmNotice? _wanted;

  /// What was last sent to the platform. Starts unknown: a notification
  /// from before the app was killed may still be waiting, so the first
  /// update always cancels or replaces it.
  Object? _scheduled = _unknown;
  static const _unknown = Object();
  bool _closed = false;

  /// Platform calls run one after another, in the order asked.
  Future<void> _queue = Future.value();

  /// Completes when every call asked so far has run (for tests).
  Future<void> get idle => _queue;

  /// The rest the screen shows now; null when not resting.
  void rest(RestAlarmNotice? notice) {
    final before = _wanted;
    _wanted = notice;
    if (notice == null && before != null && !_closed && !_inBackground) {
      // The screen ends a rest at 0:00 (it ticks every 250 ms). Skipped
      // early: not over yet. Over long ago: it rang in the background.
      final over = _clock().difference(before.at);
      if (!over.isNegative && over <= ringWindow) {
        _run(() => _alarm.ringNow(before));
      }
    }
    _apply();
  }

  /// How soon after the rest's end the screen must notice it to ring.
  static const ringWindow = Duration(seconds: 2);

  /// Any state but `resumed` counts as not in front: `inactive` comes
  /// first on iOS when the phone is locked or the app switcher opens, so
  /// the notification is scheduled before the app is suspended.
  void lifecycle(AppLifecycleState state) {
    _inBackground = state != AppLifecycleState.resumed;
    _apply();
  }

  /// The screen is gone (closed or finished): nothing may ring.
  Future<void> close() {
    _closed = true;
    _wanted = null;
    _scheduled = _unknown;
    _apply();
    return _queue;
  }

  void _apply() {
    final wanted = _wanted;
    final target =
        !_closed &&
            _inBackground &&
            wanted != null &&
            wanted.at.isAfter(_clock())
        ? wanted
        : null;
    if (target == _scheduled) return;
    _scheduled = target;
    _run(() => target == null ? _alarm.cancel() : _alarm.schedule(target));
  }

  /// The member's first rest: ask once whether the app may ring. Returns
  /// the answer (the screen explains [RestAlarmAccess.needsOnTime]).
  Future<RestAlarmAccess> firstRest() async {
    try {
      final access = await _alarm.askOnce();
      if (access != RestAlarmAccess.alreadyAsked) {
        unawaited(
          Analytics.capture('rest_alarm_answered', {
            'allowed': access != RestAlarmAccess.denied,
            'on_time': access == RestAlarmAccess.allowed,
          }),
        );
      }
      return access;
    } on Object catch (error, stackTrace) {
      unawaited(Monitoring.captureException(error, stackTrace));
      return RestAlarmAccess.alreadyAsked;
    }
  }

  /// Notifications never break the workout: failures are reported only.
  void _run(Future<void> Function() call) {
    _queue = _queue.then((_) async {
      try {
        await call();
      } on Object catch (error, stackTrace) {
        await Monitoring.captureException(error, stackTrace);
      }
    });
  }
}
