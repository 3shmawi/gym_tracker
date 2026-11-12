import 'dart:convert';

import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/backup/domain/entities/restore.dart';
import 'package:gym_tracker/features/backup/domain/repositories/backup_repositories.dart';
import 'package:gym_tracker/features/backup/domain/usecases/fingerprints.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/repositories/restore_sink.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';

/// Brings the account's training onto this phone (docs/designs/
/// never_lose_history.md §4). Never deletes or changes a workout on the
/// phone: workouts are added (the key is their content, so none is ever
/// twice), and the plan, level and chosen day follow the rules below.
///
/// * Workouts come down 200 at a time, oldest first, and the position is
///   saved after every page, so a dropped connection carries on where it
///   stopped (a later call resumes). They arrive marked as backed up.
/// * The plan: the phone has none → the account's; the same → nothing; both
///   and different → [PlanNeedsChoice] and nothing is changed until the person
///   chooses ([resolvePlan]); the plan that loses is kept for 30 days.
/// * The best level is the higher of the two; the chosen day is the
///   account's only when the phone has none.
class RunRestore {
  const new({
    required this.remote,
    required this.sink,
    required this.settings,
    required this.workouts,
    this.pageSize = 200,
    this.now = DateTime.now,
  });

  final BackupRemote remote;
  final RestoreSink sink;
  final BackupSettings settings;
  final WorkoutRepository workouts;
  final int pageSize;
  final DateTime Function() now;

  /// How long the plan that lost a conflict is kept.
  static const keepFor = Duration(days: 30);

  /// Runs (or resumes) the restore. [onProgress] hears the number of workouts
  /// added so far. A failure keeps what was taken and the position: calling
  /// again carries on.
  Future<Result<RestoreSummary>> call({
    void Function(int added)? onProgress,
  }) async {
    var added = 0;
    var skipped = 0;

    // 1. Workouts.
    if (settings.restoreCursor != RestoreCursor.done) {
      var cursor = RestoreCursor.parse(settings.restoreCursor);
      while (true) {
        final page = await remote.fetchSessions(after: cursor, limit: pageSize);
        switch (page) {
          case Failed(:final failure):
            return Failed(failure);
          case Success(:final value):
            added += await sink.addBackedUp(value.sessions);
            skipped += value.skipped;
            onProgress?.call(added);
            cursor = value.next;
            await settings.setRestoreCursor(
              cursor?.toString() ?? RestoreCursor.done,
            );
        }
        if (cursor == null) break;
      }
    }

    // 2. The plan.
    final PlanOutcome outcome;
    switch (await remote.fetchPlan()) {
      case Failed(:final failure):
        return Failed(failure);
      case Success(:final value):
        outcome = await _plan(value);
    }

    // 3. Best level and chosen day.
    var levelRaised = false;
    var dayTaken = false;
    switch (await remote.fetchState()) {
      case Failed(:final failure):
        return Failed(failure);
      case Success(:final value) when value != null:
        final mine = await workouts.loadBestLevel();
        if (mine case Success(value: final level)
            when value.bestLevel.index > level.index) {
          await workouts.saveBestLevel(value.bestLevel);
          levelRaised = true;
        }
        final day = await workouts.loadChosenDay();
        if (day case Success(value: null) when value.chosenDay != null) {
          await workouts.saveChosenDay(value.chosenDay);
          dayTaken = true;
        }
        // When the phone now holds what the account holds, it is not sent
        // again.
        final now = (
          await workouts.loadBestLevel(),
          await workouts.loadChosenDay(),
        );
        if (now case (Success(value: final level), Success(value: final chosen))
            when level == value.bestLevel && chosen == value.chosenDay) {
          await settings.setStateFingerprint(stateFingerprint(level, chosen));
        }
      case Success():
        break;
    }

    return Success(
      RestoreSummary(
        sessionsAdded: added,
        skipped: skipped,
        plan: outcome,
        levelRaised: levelRaised,
        chosenDayTaken: dayTaken,
      ),
    );
  }

  Future<PlanOutcome> _plan(RemotePlan? account) async {
    if (account == null) return const PlanNone();
    final mine = await workouts.loadPlan();
    // A plan on the phone that cannot be read: leave everything as it is.
    if (mine is Failed<WorkoutPlan?>) return const PlanNone();
    final phone = (mine as Success<WorkoutPlan?>).value;
    final print = planFingerprint(account.plan);
    if (phone == null) {
      await workouts.savePlan(account.plan);
      await settings.setPlan(version: account.version, fingerprint: print);
      await settings.setPlanConflict(value: false);
      return const PlanTookAccount();
    }
    if (planFingerprint(phone) == print) {
      await settings.setPlan(version: account.version, fingerprint: print);
      await settings.setPlanConflict(value: false);
      return const PlanSame();
    }
    return PlanNeedsChoice(account, phone);
  }

  /// The person's answer to a [PlanNeedsChoice]: the plan that stays is
  /// written, the other is kept on the phone for 30 days.
  Future<void> resolvePlan(PlanNeedsChoice need, PlanChoice choice) async {
    switch (choice) {
      case PlanChoice.account:
        await workouts.savePlan(need.account.plan);
        await settings.setPlan(
          version: need.account.version,
          fingerprint: planFingerprint(need.account.plan),
        );
        await settings.setKeptPlan(jsonEncode(need.phone.toJson()), now());
      case PlanChoice.thisPhone:
        // The account's plan is now the base: the next backup run saves this
        // phone's plan on top of it (an empty fingerprint never matches).
        await settings.setPlan(version: need.account.version, fingerprint: '');
        await settings.setKeptPlan(
          jsonEncode(need.account.plan.toJson()),
          now(),
        );
    }
    await settings.setPlanConflict(value: false);
  }
}
