import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/domain/games/game_rules.dart';
import 'package:meta/meta.dart';

/// One floor of the tower: one counted rep.
@immutable
class StackFloor {
  const new({required this.steady, required this.offset});

  /// Top to top in [RoundState.steadyRep] or more: drawn with a green rim
  /// and worth a bonus point.
  final bool steady;

  /// How far the block sits from the centre, as a share of its width
  /// (negative: to the left). Deep reps are centred (0).
  final double offset;

  @override
  bool operator ==(Object other) =>
      other is StackFloor && other.steady == steady && other.offset == offset;

  @override
  int get hashCode => Object.hash(steady, offset);
}

@immutable
class StackState extends GameState {
  const new({this.floors = const [], this.last});

  final List<StackFloor> floors;

  @override
  final GameMoment? last;

  @override
  MoveGameId get game => MoveGameId.stack;

  int get steady => floors.where((f) => f.steady).length;

  /// Floors plus the steady bonus: the same as the round's score.
  @override
  int get score => floors.length + steady;
}

/// "Stack" («البُرج»): every counted rep drops one glass block on a tower
/// (docs/designs/move_games.md §2, concept A). A deep rep gives a centred
/// block, a steady one a green rim; half reps and rushed reps add nothing.
/// There is no way to lose.
final class StackRules implements GameRules<StackState> {
  const new();

  /// At this depth or deeper the block is perfectly centred.
  static const centredDepth = 0.95;

  /// The furthest a block sits off centre (a share of its width).
  static const maxOffset = 0.12;

  @override
  MoveGameId get id => MoveGameId.stack;

  @override
  StackState start() => const StackState();

  @override
  StackState onEvent(StackState state, RepEvent event, DateTime at) {
    final seq = (state.last?.seq ?? 0) + 1;
    switch (event) {
      case RepCounted(:final took, :final depth):
        final floors = [
          ...state.floors,
          StackFloor(
            steady: took >= RoundState.steadyRep,
            offset: offsetFor(depth, state.floors.length),
          ),
        ];
        return StackState(
          floors: List.unmodifiable(floors),
          last: GameMoment(
            kind: GameMomentKind.rep,
            at: at,
            seq: seq,
            milestone: floors.length % GameRules.milestoneEvery == 0,
          ),
        );
      case HalfRep():
        return StackState(
          floors: state.floors,
          last: GameMoment(kind: GameMomentKind.halfRep, at: at, seq: seq),
        );
      case TooFast():
        return StackState(
          floors: state.floors,
          last: GameMoment(kind: GameMomentKind.tooFast, at: at, seq: seq),
        );
      case BodyLost() || BodyFound() || FormHint():
        return state;
    }
  }

  /// Off centre by how much the rep fell short of [centredDepth], to the
  /// right on even floors and to the left on odd ones (a tower that leans
  /// one way would look like it is about to fall; it never falls).
  static double offsetFor(double depth, int floor) {
    final d = depth.isNaN ? 0.0 : depth.clamp(0.0, 1.0);
    final short = (centredDepth - d).clamp(0.0, 1.0);
    final size = (short * 0.6).clamp(0.0, maxOffset);
    if (size == 0) return 0;
    return floor.isEven ? size : -size;
  }
}
