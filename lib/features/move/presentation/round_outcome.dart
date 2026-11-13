import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/domain/move_analytics.dart';
import 'package:gym_tracker/features/move/presentation/move_providers.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:meta/meta.dart';

enum SaveState { idle, saving, saved, failed }

/// The end of a round, as the results screen shows it.
@immutable
class RoundOutcome {
  const new({
    required this.result,
    this.newBest = false,
    this.save = SaveState.idle,
  });

  final RoundResult result;

  /// More reps than any earlier round of this length.
  final bool newBest;
  final SaveState save;

  /// A round with no reps has nothing to save.
  bool get canSave => result.reps > 0;

  RoundOutcome copyWith({SaveState? save}) =>
      RoundOutcome(result: result, newBest: newBest, save: save ?? this.save);
}

/// What both round controllers do at the end: the best score, analytics
/// and saving to training history.
mixin RoundEnding {
  Ref get ref;

  /// Keeps the best and reports the round (buckets only).
  Future<RoundOutcome> finishRound(
    RoundResult result, {
    required String ended,
    double? fps,
  }) async {
    final best = await ref
        .read(moveLocalRepositoryProvider)
        .offerBest(result.exercise, result.kind, result.reps);
    unawaited(
      Analytics.capture('move_game_finished', {
        'exercise': result.exercise.id,
        'game': MoveAnalytics.game(result.exercise, result.mode),
        'mode': result.mode.name,
        'round': result.kind.id,
        'reps_bucket': MoveAnalytics.repsBucket(result.reps),
        'duration_bucket': MoveAnalytics.durationBucket(result.duration),
        'ended': ended,
        'fps_bucket': ?MoveAnalytics.fpsBucket(fps),
      }),
    );
    return RoundOutcome(
      result: result,
      newBest: best is Success<bool> && best.value,
    );
  }

  /// Saves the round as a set of the exercise; null when it can't be.
  Future<SaveState> saveRound(RoundOutcome outcome) async {
    if (!outcome.canSave || outcome.save == SaveState.saved) {
      return outcome.save;
    }
    final saved = await ref.read(saveMoveRoundProvider)(outcome.result);
    if (saved is Failed<void>) return SaveState.failed;
    unawaited(
      Analytics.capture('move_round_saved', {
        'exercise': outcome.result.exercise.id,
        'mode': outcome.result.mode.name,
      }),
    );
    // Like a finished workout: a gym uploads it, a plan change waits.
    unawaited(ref.read(workoutFinishedHookProvider)());
    return SaveState.saved;
  }
}

void reportStarted(RoundState round) => unawaited(
  Analytics.capture('move_game_started', {
    'exercise': round.exercise.id,
    'game': MoveAnalytics.game(round.exercise, round.mode),
    'mode': round.mode.name,
    'round': round.kind.id,
  }),
);
