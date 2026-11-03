import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/network/connectivity.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/core/ui/app_toast.dart';
import 'package:gym_tracker/features/gym/data/repositories/gym_workout_repository.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_plan.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_plan_repository.dart';
import 'package:gym_tracker/features/gym/domain/repositories/session_outbox.dart';
import 'package:gym_tracker/features/gym/domain/usecases/sync_gym_plan.dart';
import 'package:gym_tracker/features/gym/domain/usecases/upload_sessions.dart';
import 'package:gym_tracker/features/gym/presentation/gym_providers.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/plan_editor_controller.dart';
import 'package:gym_tracker/features/workout/presentation/progress_controller.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// Override in tests: `gymPlanRepositoryProvider.overrideWithValue(fake)`.
final gymPlanRepositoryProvider = Provider<GymPlanRepository>(
  (ref) => Dependencies.gymPlanRepository,
);
final gymPlanStoreProvider = Provider<GymPlanStore>(
  (ref) => Dependencies.gymPlanStore,
);
final sessionOutboxProvider = Provider<SessionOutbox>(
  (ref) => Dependencies.sessionOutbox,
);
final sessionUploaderProvider = Provider<SessionUploader>(
  (ref) => Dependencies.sessionUploader,
);

/// The membership of the active gym workspace, or null when training solo.
/// Only changes when the membership itself does (not on every refresh).
final activeMembershipProvider = Provider<Membership?>((ref) {
  final m = ref.watch(
    gymControllerProvider.select((s) => s.value?.activeMembership),
  );
  return m != null && m.isActive ? m : null;
});

/// What the active membership allows in the plan editor; the server checks
/// it again, this only hides and locks what would be refused.
final gymPlanPermissionsProvider = Provider<PlanPermissions>(
  (ref) => PlanPermissions.of(ref.watch(activeMembershipProvider)),
);

WorkoutRepository _scopedWorkoutRepository(Ref ref) {
  final inner = ref.watch(localWorkoutRepositoryProvider);
  final membership = ref.watch(activeMembershipProvider);
  if (membership == null) return inner;
  return GymWorkoutRepository(
    inner: inner,
    remote: ref.watch(gymPlanRepositoryProvider),
    store: ref.watch(gymPlanStoreProvider),
    outbox: ref.watch(sessionOutboxProvider),
    membership: membership,
  );
}

/// Put in the app's `ProviderScope`: the workout screens then read the gym's
/// plan while a gym workspace is active.
final List<Override> gymProviderOverrides = [
  workoutRepositoryProvider.overrideWith(_scopedWorkoutRepository),
  planPermissionsProvider.overrideWith(
    (ref) => ref.watch(gymPlanPermissionsProvider),
  ),
  workoutFinishedHookProvider.overrideWith(
    (ref) => () async {
      await ref.read(gymSyncProvider).afterWorkout();
    },
  ),
];

/// Counts "your captain updated your plan" moments; the host shows the toast.
final planUpdatedToastProvider = NotifierProvider<_Counter, int>(_Counter.new);

class _Counter extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final gymSyncProvider = Provider<GymSync>((ref) {
  final sync = GymSync(ref);
  ref.onDispose(sync.dispose);
  return sync;
});

/// Keeps the active gym's plan up to date and uploads finished workouts.
/// Nothing here throws: a failure leaves the phone's copy and the queue as
/// they are, and the next trigger (app start, back online, a workout ends,
/// the back-off timer) tries again.
class GymSync {
  new(this._ref);

  final Ref _ref;
  Timer? _retry;
  int _failures = 0;
  bool _uploading = false;

  /// 30 s, 1 min, 2 min … at most 15 min.
  static Duration backoff(int failures) => Duration(
    seconds: (30 * (1 << (failures - 1).clamp(0, 5))).clamp(30, 15 * 60),
  );

  void dispose() => _retry?.cancel();

  /// Asks the server for the active gym's plan and applies it by the rules
  /// of the decision doc: the captain's plan replaces ours, the waiting
  /// workout stays, a workout in progress waits until it ends.
  Future<void> syncPlan() async {
    final membership = _ref.read(activeMembershipProvider);
    if (membership == null) return;
    final result = await SyncGymPlan(
      _ref.read(gymPlanRepositoryProvider),
      _ref.read(gymPlanStoreProvider),
      _ref.read(localWorkoutRepositoryProvider),
    )(membership.id);
    if (!_ref.mounted || result is! Success<PlanSyncOutcome>) return;
    _applied(result.value);
  }

  Future<void> afterWorkout() async {
    final membership = _ref.read(activeMembershipProvider);
    if (membership != null) {
      final result = await SyncGymPlan(
        _ref.read(gymPlanRepositoryProvider),
        _ref.read(gymPlanStoreProvider),
        _ref.read(localWorkoutRepositoryProvider),
      ).applyPending(membership.id);
      if (_ref.mounted && result is Success<PlanSyncOutcome>) {
        // The toast was already owed when the change was set aside.
        _applied(result.value, toastNow: result.value.replaced);
      }
    }
    await uploadPending();
  }

  void _applied(PlanSyncOutcome outcome, {bool toastNow = false}) {
    if (outcome.replaced) {
      _ref
        ..invalidate(nextWorkoutControllerProvider)
        ..invalidate(planEditorControllerProvider)
        ..invalidate(progressOverviewProvider);
    }
    if (outcome.replaced || outcome.deferred) {
      unawaited(
        Analytics.capture('gym_plan_synced', {
          'replaced': outcome.replaced,
          'deferred': outcome.deferred,
        }),
      );
    }
    // A change that waits for the workout to end says so when it arrives.
    if ((outcome.toast && !outcome.deferred) || toastNow) {
      _ref.read(planUpdatedToastProvider.notifier).bump();
      unawaited(Analytics.capture('gym_plan_updated_shown'));
    }
  }

  /// Sends the finished workouts waiting in the queue.
  Future<void> uploadPending() async {
    if (_uploading || !_ref.read(accountSessionProvider).isSignedIn) return;
    _uploading = true;
    try {
      final before = await _ref.read(sessionOutboxProvider).load();
      final waiting = before is Success<List<OutboxEntry>>
          ? before.value.length
          : 0;
      if (waiting == 0) return;
      final result = await UploadSessions(
        _ref.read(sessionOutboxProvider),
        _ref.read(sessionUploaderProvider),
      )();
      if (!_ref.mounted) return;
      switch (result) {
        case Success(:final value):
          _failures = 0;
          _retry?.cancel();
          unawaited(
            Analytics.capture('gym_sessions_uploaded', {
              'count': waiting - value,
              'left': value,
            }),
          );
        case Failed():
          _failures++;
          _retry?.cancel();
          _retry = Timer(backoff(_failures), () => unawaited(uploadPending()));
      }
    } finally {
      _uploading = false;
    }
  }
}

/// Starts the syncing when the app opens, when the active gym changes, when
/// the app comes back, and when the network returns; shows the toast.
class GymSyncHost extends ConsumerStatefulWidget {
  const new({required this.child, this.onlineChanges, super.key});

  final Widget child;

  /// Defaults to the device connectivity; tests pass their own stream.
  final Stream<bool>? onlineChanges;

  @override
  ConsumerState<GymSyncHost> createState() => _GymSyncHostState();
}

class _GymSyncHostState extends ConsumerState<GymSyncHost>
    with WidgetsBindingObserver {
  StreamSubscription<bool>? _online;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _online = (widget.onlineChanges ?? ConnectivityStatus.onlineChanges)
        .where((online) => online)
        .listen((_) => _run());
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  void _run() {
    if (!mounted) return;
    final sync = ref.read(gymSyncProvider);
    unawaited(sync.syncPlan());
    unawaited(sync.uploadPending());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _run();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_online?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref
      ..listen(activeMembershipProvider, (previous, next) {
        // Another gym (or solo): the screens read another plan.
        if (previous?.id != next?.id) {
          ref
            ..invalidate(nextWorkoutControllerProvider)
            ..invalidate(planEditorControllerProvider)
            ..invalidate(progressOverviewProvider);
        }
        if (next != null) _run();
      })
      ..listen(planUpdatedToastProvider, (previous, next) {
        if (previous == next) return;
        AppToast.show(
          context.l10n.planUpdatedByCaptain,
          direction: Directionality.of(context),
        );
      });
    return widget.child;
  }
}
