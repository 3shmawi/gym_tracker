import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/domain/games/game_rules.dart';
import 'package:gym_tracker/features/move/domain/games/stack_rules.dart';
import 'package:gym_tracker/features/move/domain/move_exercises.dart';

void main() {
  const rules = StackRules();
  final t0 = DateTime(2026, 11, 12, 10);

  RepCounted rep({int ms = 1000, double depth = 1}) => RepCounted(
    total: 1,
    took: Duration(milliseconds: ms),
    depth: depth,
  );

  StackState play(List<RepEvent> events) {
    var s = rules.start();
    for (final (i, e) in events.indexed) {
      s = rules.onEvent(s, e, t0.add(Duration(seconds: i)));
    }
    return s;
  }

  test('starts empty, with nothing happened yet', () {
    final s = rules.start();
    expect(s.floors, isEmpty);
    expect(s.score, 0);
    expect(s.last, isNull);
    expect(s.game, MoveGameId.stack);
    expect(rules.id.id, 'stack');
  });

  test('a counted rep adds one floor', () {
    final s = play([rep()]);
    expect(s.floors, hasLength(1));
    expect(s.last?.kind, GameMomentKind.rep);
    expect(s.last?.seq, 1);
    expect(s.last?.at, t0);
  });

  test('a steady rep gets a green rim and a bonus point', () {
    final s = play([
      rep(ms: RoundState.steadyRep.inMilliseconds),
      rep(ms: 900),
    ]);
    expect(s.floors.map((f) => f.steady), [true, false]);
    expect(s.steady, 1);
    expect(s.score, 3);
  });

  test('the score matches the round score for the same reps', () {
    var round = const RoundState(
      exercise: MoveExerciseId.pushUps,
      kind: RoundKind.s60,
      mode: RoundMode.camera,
    ).startCountdown(t0).tick(t0.add(const Duration(seconds: 3)));
    final events = [rep(ms: 1500), rep(ms: 800), rep(ms: 2000), rep()];
    var game = rules.start();
    for (final e in events) {
      final at = t0.add(const Duration(seconds: 5));
      round = round.onEvent(e, at);
      game = rules.onEvent(game, e, at);
    }
    expect(game.score, round.score);
    expect(game.floors.length, round.reps);
  });

  test('half reps and rushed reps add nothing but are noticed', () {
    final half = play([const HalfRep(depth: 0.5)]);
    expect(half.floors, isEmpty);
    expect(half.last?.kind, GameMomentKind.halfRep);

    final fast = play([const TooFast(took: Duration(milliseconds: 400))]);
    expect(fast.floors, isEmpty);
    expect(fast.last?.kind, GameMomentKind.tooFast);
    expect(fast.score, 0);
  });

  test('body and hint events change nothing', () {
    final before = play([rep()]);
    for (final e in [
      const BodyLost(),
      const BodyFound(),
      const FormHint(FormHintKind.straightBody),
    ]) {
      expect(identical(rules.onEvent(before, e, t0), before), isTrue);
    }
  });

  test('every fifth floor is a milestone', () {
    final s = play(List.filled(10, rep()));
    expect(s.floors, hasLength(10));
    expect(s.last?.milestone, isTrue);
    final four = play(List.filled(4, rep()));
    expect(four.last?.milestone, isFalse);
    final five = play(List.filled(5, rep()));
    expect(five.last?.milestone, isTrue);
  });

  test('the moment number counts up with every moment', () {
    final s = play([rep(), const HalfRep(depth: 0.5), rep()]);
    expect(s.last?.seq, 3);
  });

  group('offset', () {
    test('deep reps are centred', () {
      expect(StackRules.offsetFor(1, 0), 0);
      expect(StackRules.offsetFor(StackRules.centredDepth, 3), 0);
    });

    test('shallower reps sit off centre, alternating sides', () {
      final even = StackRules.offsetFor(0.85, 0);
      final odd = StackRules.offsetFor(0.85, 1);
      expect(even, greaterThan(0));
      expect(odd, -even);
    });

    test('never further than the maximum, whatever the depth', () {
      for (final d in [-5.0, 0.0, 0.3, double.negativeInfinity, double.nan]) {
        final o = StackRules.offsetFor(d, 0);
        expect(o.isFinite, isTrue, reason: '$d');
        expect(o.abs(), lessThanOrEqualTo(StackRules.maxOffset));
      }
      expect(StackRules.offsetFor(double.infinity, 0), 0);
      expect(StackRules.offsetFor(7, 1), 0);
    });
  });

  test('floors cannot be changed from outside', () {
    final s = play([rep()]);
    expect(
      () => s.floors.add(const StackFloor(steady: false, offset: 0)),
      throwsUnsupportedError,
    );
  });

  test('a long round keeps every floor', () {
    final s = play(List.filled(500, rep(ms: 1400)));
    expect(s.floors, hasLength(500));
    expect(s.score, 1000);
  });

  test('the registry gives push-ups the Stack game', () {
    final game = MoveExercises.gameFor(MoveExerciseId.pushUps);
    expect(game.id, MoveGameId.stack);
    final s = game.onEvent(game.start(), rep(), t0);
    expect(s, isA<StackState>());
    expect(s.score, 1);
  });
}
