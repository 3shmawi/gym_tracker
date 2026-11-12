import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/feature_flags/feature_flags.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/backup/domain/entities/backup_status.dart';
import 'package:gym_tracker/features/backup/domain/entities/restore.dart';
import 'package:gym_tracker/features/backup/domain/repositories/backup_repositories.dart';
import 'package:gym_tracker/features/backup/domain/usecases/run_backup.dart';
import 'package:gym_tracker/features/backup/domain/usecases/run_restore.dart';
import 'package:gym_tracker/features/gym/presentation/gym_providers.dart';
import 'package:gym_tracker/features/workout/domain/repositories/restore_sink.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';

/// Override in tests.
final backupRemoteProvider = Provider<BackupRemote>(
  (ref) => Dependencies.backupRemote,
);
final backupQueueProvider = Provider<BackupQueue>(
  (ref) => Dependencies.backupQueue,
);
final backupSettingsProvider = Provider<BackupSettings>(
  (ref) => Dependencies.backupSettings,
);
final restoreSinkProvider = Provider<RestoreSink>(
  (ref) => Dependencies.restoreSink,
);

/// Whether backup shows at all (`Flags.trainingBackup`: the offer, the
/// Settings card, the sign-in link). Starts from the answer kept on the
/// phone, then asks PostHog once and remembers what it said. Backing up
/// itself runs for whoever turned it on, whatever the flag says now.
final trainingBackupEnabledProvider =
    NotifierProvider<TrainingBackupFlag, bool>(TrainingBackupFlag.new);

class TrainingBackupFlag extends Notifier<bool> {
  @override
  bool build() {
    unawaited(_refresh());
    return Dependencies.flagCache.read(Flags.trainingBackup) ?? false;
  }

  Future<void> _refresh() async {
    final bool enabled;
    try {
      enabled = await FeatureFlags.isEnabled(Flags.trainingBackup);
    } on Object {
      return; // Keep the last known answer.
    }
    if (!ref.mounted) return;
    await Dependencies.flagCache.write(Flags.trainingBackup, value: enabled);
    if (ref.mounted && state != enabled) state = enabled;
  }
}

/// Where backing up stands (for the Settings card).
final backupStatusProvider =
    NotifierProvider<BackupStatusController, BackupStatus>(
      BackupStatusController.new,
    );

class BackupStatusController extends Notifier<BackupStatus> {
  @override
  BackupStatus build() {
    final settings = ref.watch(backupSettingsProvider);
    return settings.enabled
        ? BackupStatus(
            state: BackupState.upToDate,
            lastSyncedAt: settings.lastSyncedAt,
            planConflict: settings.planConflict,
          )
        : BackupStatus.off;
  }

  // ignore: use_setters_to_change_properties, a named update, not a setter.
  void update(BackupStatus status) => state = status;
}

final backupSyncProvider = Provider<BackupSync>((ref) {
  final sync = BackupSync(ref);
  ref.onDispose(sync.dispose);
  return sync;
});

/// Runs the backup when something may have changed: the app opens or comes
/// back, the network returns, a workout ends, the plan changes, the back-off
/// timer. Nothing here throws; the training stays on the phone whatever
/// happens (docs/designs/never_lose_history.md §3).
class BackupSync {
  new(this._ref);

  final Ref _ref;
  Timer? _retry;
  int _failures = 0;
  bool _running = false;

  /// 30 s, 1 min, 2 min … at most 15 min.
  static Duration backoff(int failures) => Duration(
    seconds: (30 * (1 << (failures - 1).clamp(0, 5))).clamp(30, 15 * 60),
  );

  void dispose() => _retry?.cancel();

  /// Turns backup on for this phone and runs it. The caller has made sure
  /// the account can be written to (signed in with an email).
  Future<void> enable() async {
    final settings = _ref.read(backupSettingsProvider);
    await settings.setEnabled(value: true);
    unawaited(Analytics.capture('backup_enabled'));
    await run();
  }

  /// Stops backing up and erases what the account holds of it
  /// (`delete_my_backup`). Backup is only turned off when the erase worked,
  /// so nothing is left behind by mistake; false = nothing changed.
  Future<bool> disableAndErase() async {
    final result = await _ref.read(backupRemoteProvider).deleteBackup();
    if (result is Failed<void>) return false;
    unawaited(Analytics.capture('backup_erased'));
    await _ref.read(backupQueueProvider).resetAll();
    await _forget();
    return true;
  }

  /// Stops backing up. What is already on the account stays there.
  Future<void> disable() async {
    await _forget();
  }

  Future<void> _forget() async {
    _retry?.cancel();
    final settings = _ref.read(backupSettingsProvider);
    await settings.setEnabled(value: false);
    // A later "on" starts from nothing: the account has no plan or workouts
    // now, so the old versions and fingerprints must not hide what is new.
    await settings.setPlan(version: 0, fingerprint: '');
    await settings.setStateFingerprint('');
    if (_ref.mounted) {
      _ref.read(backupStatusProvider.notifier).update(BackupStatus.off);
    }
    unawaited(Analytics.capture('backup_disabled'));
  }

  /// A restore that was started and not finished (the app was closed, the
  /// network dropped) goes on in the background, from the saved position. A
  /// plan conflict it meets is left for the card to say (nothing is
  /// changed): the person is asked the next time they sign in.
  Future<void> _resumeRestore(BackupSettings settings) async {
    final cursor = settings.restoreCursor;
    if (cursor == null || cursor == RestoreCursor.done) return;
    final result = await RunRestore(
      remote: _ref.read(backupRemoteProvider),
      sink: _ref.read(restoreSinkProvider),
      settings: settings,
      workouts: _ref.read(localWorkoutRepositoryProvider),
      now: _ref.read(clockProvider),
    )();
    if (result case Success(:final value) when value.plan is PlanNeedsChoice) {
      await settings.setPlanConflict(value: true);
    }
  }

  Future<void> run() async {
    final settings = _ref.read(backupSettingsProvider);
    if (_running || !settings.enabled) return;
    if (!_ref.read(accountSessionProvider).isSignedIn) {
      _ref
          .read(backupStatusProvider.notifier)
          .update(const BackupStatus(state: BackupState.signInAgain));
      return;
    }
    _running = true;
    try {
      await _resumeRestore(settings);
      if (!_ref.mounted) return;
      final queue = _ref.read(backupQueueProvider);
      final before = await queue.pendingCount();
      final status = await RunBackup(
        remote: _ref.read(backupRemoteProvider),
        queue: queue,
        settings: settings,
        workouts: _ref.read(localWorkoutRepositoryProvider),
      )();
      if (!_ref.mounted) return;
      _ref.read(backupStatusProvider.notifier).update(status);
      switch (status.state) {
        case BackupState.upToDate:
          _failures = 0;
          _retry?.cancel();
          if (before > 0) unawaited(Analytics.capture('backup_synced'));
        case BackupState.waiting:
          _failures++;
          _retry?.cancel();
          _retry = Timer(backoff(_failures), () => unawaited(run()));
          if (_failures == 1) {
            unawaited(
              Analytics.capture('backup_failed', {'reason': 'network'}),
            );
          }
        case BackupState.failed:
          _failures = 0;
          _retry?.cancel();
          unawaited(Analytics.capture('backup_failed', {'reason': 'refused'}));
        case BackupState.signInAgain:
          unawaited(Analytics.capture('backup_failed', {'reason': 'signin'}));
        case BackupState.off:
          break;
      }
    } finally {
      _running = false;
    }
  }
}
