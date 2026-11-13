import 'package:gym_tracker/features/move/domain/detectors/push_up_detector.dart';
import 'package:gym_tracker/features/move/domain/detectors/rep_detector.dart';
import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:gym_tracker/features/move/domain/games/game_rules.dart';
import 'package:gym_tracker/features/move/domain/games/stack_rules.dart';

/// What is specific to each exercise. Adding one (pull-ups, squats…) is a
/// new [MoveExerciseId], a detector here, its placement guide, its game
/// and its catalog entry (docs/designs/move_games.md §4.4).
abstract final class MoveExercises {
  /// A fresh detector for one round.
  static RepDetector detectorFor(MoveExerciseId id) => switch (id) {
    MoveExerciseId.pushUps => PushUpDetector(),
  };

  /// The game a camera round of [id] plays. Any rep can build a tower, so
  /// new exercises can start with Stack.
  static GameRules<GameState> gameFor(MoveExerciseId id) => switch (id) {
    MoveExerciseId.pushUps => const _Erased(StackRules()),
  };
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
