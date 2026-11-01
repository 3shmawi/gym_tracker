import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/workout/domain/services/rest_alarm.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_view.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/rest_alarm_sync.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/rest_on_time_sheet.dart';
import 'package:gym_tracker/l10n/l10n.dart';

class ActiveWorkoutPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ActiveWorkoutPage> createState() => _ActiveWorkoutPageState();
}

class _ActiveWorkoutPageState extends ConsumerState<ActiveWorkoutPage>
    with WidgetsBindingObserver {
  late final RestAlarmSync _alarm;

  /// Read in build, used when the app leaves the front.
  AppLocalizations? _l10n;
  String _lang = 'en';

  @override
  void initState() {
    super.initState();
    _alarm = RestAlarmSync(
      ref.read(restAlarmProvider),
      now: ref.read(clockProvider),
    );
    WidgetsBinding.instance.addObserver(this);
    _alarm.lifecycle(
      WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _alarm
      ..rest(_notice(ref.read(activeWorkoutControllerProvider).value))
      ..lifecycle(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_alarm.close());
    super.dispose();
  }

  /// "Rest over · Squat · set 2": the set waiting after this rest.
  RestAlarmNotice? _notice(ActiveWorkout? workout) {
    final l10n = _l10n;
    final ends = workout?.draft.restEndsAt;
    final cursor = workout?.cursor;
    if (l10n == null || workout == null || ends == null || cursor == null) {
      return null;
    }
    final exercise = workout.day.exercises[cursor.exerciseIndex];
    return RestAlarmNotice(
      at: ends,
      title: l10n.restOverTitle,
      body: l10n.restOverBody(exercise.name.of(_lang), cursor.setNumber),
      channelName: l10n.restChannelName,
    );
  }

  Future<void> _firstRest() async {
    final access = await _alarm.firstRest();
    if (access != RestAlarmAccess.needsOnTime || !mounted) return;
    if (await showRestOnTimeSheet(context)) {
      await ref.read(restAlarmProvider).openOnTimeSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    _l10n = context.l10n;
    _lang = Localizations.localeOf(context).languageCode;
    ref.listen(activeWorkoutControllerProvider, (previous, next) {
      final rest = next.value?.draft.restEndsAt;
      _alarm.rest(_notice(next.value));
      if (rest != null && previous?.value?.draft.restEndsAt == null) {
        unawaited(_firstRest());
      }
    });

    final controller = ref.read(activeWorkoutControllerProvider.notifier);
    void home() =>
        context.canPop() ? context.pop() : context.go(AppRoutes.home);
    return ActiveWorkoutView(
      state: ref.watch(activeWorkoutControllerProvider),
      now: ref.watch(clockProvider),
      actions: ActiveWorkoutActions(
        onLog: (w, r) => unawaited(controller.logSet(weight: w, reps: r)),
        onEditSet: (i, w, r) =>
            unawaited(controller.editSet(i, weight: w, reps: r)),
        onDeleteSet: (i) => unawaited(controller.deleteSet(i)),
        onAdd15: () =>
            unawaited(controller.addRest(const Duration(seconds: 15))),
        onEndRest: () => unawaited(controller.endRest()),
        onFinish: () async {
          if (await controller.finish() && context.mounted) home();
        },
        onClose: home,
        onRetry: () => unawaited(controller.retry()),
      ),
    );
  }
}
