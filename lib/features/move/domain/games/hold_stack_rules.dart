import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/domain/games/game_rules.dart';
import 'package:gym_tracker/features/move/domain/games/stack_rules.dart';

/// The tower for a hold (plank, docs/designs/plank_hold.md §5): every
/// [secondsPerBlock] seconds held drop one centred, steady block. Each held
/// second arrives as a [RepCounted] (its `total` is the seconds held); the
/// other seconds and every other event leave the tower as it is. Same game
/// ([MoveGameId.stack]), same drawing; no way to lose.
final class HoldStackRules implements GameRules<StackState> {
  const new();

  static const secondsPerBlock = 5;
  static const _stack = StackRules();

  @override
  MoveGameId get id => MoveGameId.stack;

  @override
  StackState start() => _stack.start();

  @override
  StackState onEvent(StackState state, RepEvent event, DateTime at) =>
      switch (event) {
        RepCounted(:final total) when total % secondsPerBlock == 0 =>
          _stack.onEvent(
            state,
            const RepCounted(total: 0, took: RoundState.steadyRep, depth: 1),
            at,
          ),
        RepCounted() || HalfRep() || TooFast() => state,
        BodyLost() || BodyFound() || FormHint() => state,
      };
}
