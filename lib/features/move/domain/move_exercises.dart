import 'package:gym_tracker/features/move/domain/detectors/plank_detector.dart';
import 'package:gym_tracker/features/move/domain/detectors/push_up_detector.dart';
import 'package:gym_tracker/features/move/domain/detectors/rep_detector.dart';
import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/domain/games/game_rules.dart';
import 'package:gym_tracker/features/move/domain/games/hold_stack_rules.dart';
import 'package:gym_tracker/features/move/domain/games/stack_rules.dart';

/// What is specific to each exercise. Adding one (pull-ups, squats…) is a
/// new [MoveExerciseId], a detector here, its placement guide, its game
/// and its catalog entry (docs/designs/move_games.md §4.4).
abstract final class MoveExercises {
  /// A fresh detector for one round.
  static RepDetector detectorFor(MoveExerciseId id) => switch (id) {
    MoveExerciseId.pushUps => PushUpDetector(),
    MoveExerciseId.plank => PlankDetector(),
  };

  /// The game a camera round of [id] plays. Any rep can build a tower, so
  /// new exercises can start with Stack.
  static GameRules<GameState> gameFor(MoveExerciseId id) => switch (id) {
    MoveExerciseId.pushUps => const _Erased(StackRules()),
    MoveExerciseId.plank => const _Erased(HoldStackRules()),
  };

  /// The round lengths the hub offers for [id], in their order.
  static List<RoundKind> roundsFor(MoveExerciseId id) => switch (id) {
    MoveExerciseId.pushUps => const [
      RoundKind.s30,
      RoundKind.s60,
      RoundKind.r10,
      RoundKind.r20,
    ],
    MoveExerciseId.plank => const [
      RoundKind.h30,
      RoundKind.h45,
      RoundKind.h60,
      RoundKind.hMax,
    ],
  };

  /// The round chosen first in the hub.
  static RoundKind defaultFor(MoveExerciseId id) => switch (id) {
    MoveExerciseId.pushUps => RoundKind.fallback,
    MoveExerciseId.plank => RoundKind.h30,
  };

  /// The round [id] names, if [exercise] offers it; else its default (a
  /// link can't pair a plank with a push-up round).
  static RoundKind kindFor(MoveExerciseId exercise, String? id) =>
      roundsFor(exercise).where((k) => k.id == id).firstOrNull ??
      defaultFor(exercise);

  /// A best is kept for this round: not for a hold with a target, which
  /// always ends at its target.
  static bool keepsBest(RoundKind kind) => !kind.hold || kind.target == null;
}

/// Lets the screen hold any game's rules without knowing its state type.
final class _Erased<S extends GameState> implements GameRules<GameState> {
  const new(this.rules);

  final GameRules<S> rules;

  @override
  MoveGameId get id => rules.id;

  @override
  GameState start() => rules.start();

  @override
  GameState onEvent(GameState state, RepEvent event, DateTime at) =>
      state is S ? rules.onEvent(state, event, at) : state;
}
