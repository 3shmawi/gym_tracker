import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:meta/meta.dart';

/// The games a rep can drive. The [id] is stored (analytics `game`) and
/// never reused.
enum MoveGameId {
  stack('stack');

  new(this.id);

  final String id;
}

/// What the last event did in the game: the screen plays a sound or shows
/// a notice for it, and the drawing animates it.
enum GameMomentKind {
  /// A counted rep added to the game (a block on the tower).
  rep,

  /// A half rep: nothing is added; the game shows "go lower".
  halfRep,

  /// A rep that was too fast: nothing is added; the game shows "slow down".
  tooFast,
}

@immutable
class GameMoment {
  const new({
    required this.kind,
    required this.at,
    required this.seq,
    this.milestone = false,
  });

  final GameMomentKind kind;

  /// When it happened (the round's clock).
  final DateTime at;

  /// Counts up with every moment: a drawing knows a moment is new.
  final int seq;

  /// Every [GameRules.milestoneEvery] reps: a different sound.
  final bool milestone;

  @override
  bool operator ==(Object other) =>
      other is GameMoment &&
      other.kind == kind &&
      other.at == at &&
      other.seq == seq &&
      other.milestone == milestone;

  @override
  int get hashCode => Object.hash(kind, at, seq, milestone);
}

/// A game's state. Immutable; only [GameRules] makes new ones.
abstract class GameState {
  const new();

  MoveGameId get game;

  /// Reps plus bonuses (game points, never saved as training).
  int get score;

  /// The last thing that happened, or null before the first event.
  GameMoment? get last;
}

/// The rules of one game, pure Dart (docs/designs/move_games.md §3): the
/// detector's events go in, a new [GameState] comes out. Drawing (Flame)
/// only reads the state, so every rule is tested without Flame.
///
/// A game has no fail state and no rule about time: a round ends on its
/// time or target, never in the game.
abstract interface class GameRules<S extends GameState> {
  MoveGameId get id;

  /// The state before the first rep.
  S start();

  /// What [event] does to [state]. Only called while the round runs.
  S onEvent(S state, RepEvent event, DateTime at);

  /// Every this many reps the game marks a milestone.
  static const milestoneEvery = 5;
}
