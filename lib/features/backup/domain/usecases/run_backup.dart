import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/backup/domain/entities/backup_status.dart';
import 'package:gym_tracker/features/backup/domain/repositories/backup_repositories.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';

/// One backup run: the waiting workouts, then the plan, then the level and
/// chosen day. Nothing on the phone is ever changed or deleted, a failure
/// stops the run and the next trigger (app start, back online, a workout
/// ends, the back-off) carries on where it stopped.
///
/// Rules (docs/designs/never_lose_history.md §3):
/// * workouts are immutable and keyed by content: two phones simply add up;
/// * a workout the server refuses is kept on the phone with a reason and
///   does not hold back the others;
/// * the plan saved first wins: when the account's plan is newer, this
///   phone's is not uploaded (the restore step asks which to keep);
/// * the best level only goes up on the server; the chosen day is last write.
class RunBackup {
  const new({
    required this.remote,
    required this.queue,
    required this.settings,
    required this.workouts,
    this.chunk = 50,
    this.now = DateTime.now,
  });

  final BackupRemote remote;
  final BackupQueue queue;
  final BackupSettings settings;
  final WorkoutRepository workouts;
  final int chunk;
  final DateTime Function() now;

  /// How the run ended, as the status the Settings card shows.
  Future<BackupStatus> call() async {
    if (!settings.enabled) return BackupStatus.off;

    final person = await remote.ensurePerson();
    if (person case Failed(:final failure)) return await _stopped(failure);

    // 1. Workouts, oldest first, one chunk at a time.
    while (true) {
      final batch = await queue.pending(chunk);
      if (batch.isEmpty) break;
      final sent = await remote.uploadSessions(batch);
      switch (sent) {
        case Success():
          await queue.markSynced([for (final s in batch) s.clientId]);
        case Failed(:final failure) when failure is ValidationFailure:
          // One bad workout must not hold back the rest: try them one by one.
          for (final session in batch) {
            final one = await remote.uploadSessions([session]);
            switch (one) {
              case Success():
                await queue.markSynced([session.clientId]);
              case Failed(:final failure) when failure is ValidationFailure:
                await queue.markProblem(session.clientId, 'refused');
              case Failed(:final failure):
                return await _stopped(failure);
            }
          }
        case Failed(:final failure):
          return await _stopped(failure);
      }
    }

    // 2. The plan.
    final plan = await workouts.loadPlan();
    if (plan case Success(:final value) when value != null) {
      final print = _fingerprint(jsonEncode(value.toJson()));
      if (print != settings.planFingerprint && !settings.planConflict) {
        final saved = await remote.savePlan(settings.planVersion, value);
        switch (saved) {
          case Success(:final value):
            await settings.setPlan(version: value, fingerprint: print);
          case Failed(:final failure) when failure is PlanChangedFailure:
            await settings.setPlanConflict(value: true);
          case Failed(:final failure) when failure is ValidationFailure:
            // A plan the server will not take: keep it on the phone.
            break;
          case Failed(:final failure):
            return await _stopped(failure);
        }
      }
    }

    // 3. Best level and chosen day.
    final state = (
      await workouts.loadBestLevel(),
      await workouts.loadChosenDay(),
    );
    if (state case (
      Success(value: final bestLevel),
      Success(value: final chosen),
    )) {
      final print = _fingerprint(
        '${bestLevel.name}|${jsonEncode(chosen?.toJson())}',
      );
      if (print != settings.stateFingerprint) {
        final saved = await remote.saveState(bestLevel, chosen);
        switch (saved) {
          case Success():
            await settings.setStateFingerprint(print);
          case Failed(:final failure) when failure is ValidationFailure:
            break;
          case Failed(:final failure):
            return await _stopped(failure);
        }
      }
    }

    final pending = await queue.pendingCount();
    final problems = await queue.problemCount();
    if (pending == 0) await settings.setLastSyncedAt(now());
    return BackupStatus(
      state: pending > 0
          ? BackupState.waiting
          : problems > 0
          ? BackupState.failed
          : BackupState.upToDate,
      pending: pending,
      problems: problems,
      lastSyncedAt: settings.lastSyncedAt,
      planConflict: settings.planConflict,
    );
  }

  Future<BackupStatus> _stopped(AppFailure failure) async {
    final pending = await queue.pendingCount();
    return BackupStatus(
      state: failure is UnauthorizedFailure
          ? BackupState.signInAgain
          : BackupState.waiting,
      pending: pending,
      problems: await queue.problemCount(),
      lastSyncedAt: settings.lastSyncedAt,
      planConflict: settings.planConflict,
    );
  }

  static String _fingerprint(String text) =>
      sha256.convert(utf8.encode(text)).toString();
}
