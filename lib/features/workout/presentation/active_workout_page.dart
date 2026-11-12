import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/router/link_guard.dart';
import 'package:gym_tracker/features/backup/presentation/backup_offer.dart';
import 'package:gym_tracker/features/gym/presentation/gym_sync.dart';
import 'package:gym_tracker/features/video/presentation/mini_player.dart';
import 'package:gym_tracker/features/workout/domain/services/rest_alarm.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_view.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/rest_alarm_sync.dart';
import 'package:gym_tracker/features/workout/presentation/widgets/rest_on_time_sheet.dart';

class ActiveWorkoutPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ActiveWorkoutPage> createState() => _ActiveWorkoutPageState();
}

/// The "Rest over" alarm itself is app-wide (`RestAlarmHost`): it keeps
/// ringing after this screen is closed mid-rest. This screen asks for the
/// permission at the first rest.
class _ActiveWorkoutPageState extends ConsumerState<ActiveWorkoutPage>
    with WidgetsBindingObserver, IgnoresLinks {
  late final MiniPlayerReserveController _reserve;

  @override
  void initState() {
    super.initState();
    // For IgnoresLinks (links don't open over a workout).
    WidgetsBinding.instance.addObserver(this);
    // Read now: ref can't be used in dispose.
    _reserve = ref.read(miniPlayerBottomReserveProvider.notifier);
  }

  @override
  void dispose() {
    // The dock is gone: the floating video may use the bottom again (after
    // this frame: providers can't change while the tree is being built).
    final reserve = _reserve;
    scheduleMicrotask(() => reserve.set(0));
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _firstRest() async {
    final access = await ref.read(restAlarmSyncProvider).firstRest();
    if (access != RestAlarmAccess.needsOnTime || !mounted) return;
    if (await showRestOnTimeSheet(context)) {
      await ref.read(restAlarmProvider).openOnTimeSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(activeWorkoutControllerProvider, (previous, next) {
      final rest = next.value?.draft.restEndsAt;
      if (rest != null && previous?.value?.draft.restEndsAt == null) {
        unawaited(_firstRest());
      }
    });

    final controller = ref.read(activeWorkoutControllerProvider.notifier);
    void home() =>
        context.canPop() ? context.pop() : context.go(AppRoutes.home);
    return ActiveWorkoutView(
      state: ref.watch(activeWorkoutControllerProvider),
      covers: ref.watch(exerciseCoversProvider),
      now: ref.watch(clockProvider),
      onDockHeight: ref.reserveBottom,
      actions: ActiveWorkoutActions(
        onLog: (w, r) => unawaited(controller.logSet(weight: w, reps: r)),
        onPick: (i) => unawaited(controller.pick(i)),
        onEditSet: (i, w, r) =>
            unawaited(controller.editSet(i, weight: w, reps: r)),
        onDeleteSet: (i) => unawaited(controller.deleteSet(i)),
        onAdd15: () =>
            unawaited(controller.addRest(const Duration(seconds: 15))),
        onEndRest: () => unawaited(controller.endRest()),
        onFinish: () async {
          if (await controller.finish() && context.mounted) {
            unawaited(ref.read(backupOfferProvider.notifier).afterWorkout());
            home();
          }
        },
        onClose: home,
        onRetry: () => unawaited(controller.retry()),
        // The library's exercise screen (pictures, steps, video); back
        // returns to the same set.
        onHowTo: (id) =>
            unawaited(context.push<void>(AppRoutes.libraryExercise(id))),
      ),
    );
  }
}
