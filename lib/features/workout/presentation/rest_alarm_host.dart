import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/router/link_guard.dart';
import 'package:gym_tracker/features/workout/domain/services/rest_alarm.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/rest_alarm_sync.dart';
import 'package:gym_tracker/features/workout/presentation/workout_pill_host.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// "Rest over · Squat · set 2": the set waiting after this rest, or null
/// when no rest is running.
RestAlarmNotice? restAlarmNotice(
  ActiveWorkout? workout,
  AppLocalizations l10n,
  String lang,
) {
  final ends = workout?.draft.restEndsAt;
  final cursor = workout?.cursor;
  if (workout == null || ends == null || cursor == null) return null;
  final exercise = workout.day.exercises[cursor.exerciseIndex];
  return RestAlarmNotice(
    at: ends,
    title: l10n.restOverTitle,
    body: l10n.restOverBody(exercise.name.of(lang), cursor.setNumber),
    channelName: l10n.restChannelName,
  );
}

/// Keeps the "Rest over" notification in step with the workout in
/// progress from anywhere in the app (mounted in `AppShell`), so leaving
/// the workout screen mid-rest (the workout pill) still rings:
/// - app in the background or the phone locked: the notification is
///   scheduled for the rest's end ([RestAlarmSync]);
/// - app in front on another screen: it rings when the rest runs out (the
///   workout screen rings by itself when it is the one showing).
class RestAlarmHost extends ConsumerStatefulWidget {
  const new({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<RestAlarmHost> createState() => _RestAlarmHostState();
}

class _RestAlarmHostState extends ConsumerState<RestAlarmHost>
    with WidgetsBindingObserver, IgnoresLinks {
  late final RestAlarmSync _sync;
  AppLocalizations? _l10n;
  String _lang = 'en';
  Timer? _ring;
  DateTime? _ringFor;

  @override
  void initState() {
    super.initState();
    _sync = ref.read(restAlarmSyncProvider);
    WidgetsBinding.instance.addObserver(this);
    // The first update after a launch always cancels: a notification left
    // by a killed app never rings over the screen.
    _sync.lifecycle(
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _update(ref.read(activeWorkoutControllerProvider).value);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _sync
      ..rest(_notice(ref.read(activeWorkoutControllerProvider).value))
      ..lifecycle(state);
  }

  @override
  void dispose() {
    _ring?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  RestAlarmNotice? _notice(ActiveWorkout? workout) {
    final l10n = _l10n;
    if (l10n == null) return null;
    return restAlarmNotice(workout, l10n, _lang);
  }

  void _update(ActiveWorkout? workout) {
    final notice = _notice(workout);
    _sync.rest(notice);
    _armRing(notice);
  }

  /// In front, away from the workout screen: ring at the rest's end.
  void _armRing(RestAlarmNotice? notice) {
    if (notice?.at == _ringFor) return;
    _ring?.cancel();
    _ring = null;
    _ringFor = notice?.at;
    if (notice == null) return;
    final wait = notice.at.difference(ref.read(clockProvider)());
    if (wait.isNegative) return;
    _ring = Timer(wait, () {
      if (!mounted) return;
      final current = _notice(ref.read(activeWorkoutControllerProvider).value);
      if (current?.at != notice.at) return;
      if (ref.read(currentPathProvider) == AppRoutes.workout) return;
      _sync.ringInFront(current!);
    });
  }

  @override
  Widget build(BuildContext context) {
    _l10n = context.l10n;
    _lang = Localizations.localeOf(context).languageCode;
    ref.listen(
      activeWorkoutControllerProvider,
      (previous, next) => _update(next.value),
    );
    return widget.child;
  }
}
