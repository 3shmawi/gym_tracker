import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/domain/move_analytics.dart';

final t0 = DateTime(2026, 11, 12, 18);
DateTime at(int ms) => t0.add(Duration(milliseconds: ms));

RoundState fresh(RoundKind kind, {RoundMode mode = RoundMode.camera}) =>
    RoundState(exercise: MoveExerciseId.pushUps, kind: kind, mode: mode);

/// Started: the countdown ran from t0, so it runs from 3 s.
RoundState running(RoundKind kind, {RoundMode mode = RoundMode.camera}) =>
    fresh(kind, mode: mode).startCountdown(t0).tick(at(3000));

const rep = RepCounted(total: 1, took: Duration(milliseconds: 1000), depth: 1);
const slowRep = RepCounted(
  total: 1,
  took: Duration(milliseconds: 1600),
  depth: 1,
);

void main() {
  group('RoundKind', () {
    test('ids are stable and unknown ids fall back to 60 s', () {
      expect(
        [for (final k in RoundKind.values) k.id],
        ['s30', 's60', 'r10', 'r20'],
      );
      expect(RoundKind.fromId('r10'), RoundKind.r10);
      expect(RoundKind.fromId('x'), RoundKind.s60);
      expect(RoundKind.fromId(null), RoundKind.s60);
    });
  });

  group('RoundState', () {
    test('3-2-1, then running from the end of the countdown', () {
      final c = fresh(RoundKind.s30).startCountdown(t0);
      expect(c.phase, RoundPhase.countdown);
      expect(c.countdownLeft(at(100)), 3);
      expect(c.countdownLeft(at(2100)), 1);
      expect(c.tick(at(2999)).phase, RoundPhase.countdown);
      final r = c.tick(at(3200));
      expect(r.phase, RoundPhase.running);
      expect(r.startedAt, at(3000));
      expect(r.clock(at(13000)), const Duration(seconds: 20));
    });

    test('reps before the start or after the end never count', () {
      final ready = fresh(RoundKind.s30);
      expect(ready.onEvent(rep, t0).reps, 0);
      expect(ready.addRep(t0).reps, 0);
      final done = running(RoundKind.s30).end(at(5000));
      expect(done.onEvent(rep, at(6000)).reps, 0);
    });

    test('a timed round ends on time, with the time exact', () {
      var s = running(RoundKind.s30).onEvent(rep, at(5000));
      s = s.tick(at(40000));
      expect(s.phase, RoundPhase.finished);
      expect(s.endedAt, at(33000));
      expect(s.banked, const Duration(seconds: 30));
      expect(s.reps, 1);
    });

    test('a target round ends at the target', () {
      var s = running(RoundKind.r10, mode: RoundMode.manual);
      for (var i = 0; i < 10; i++) {
        s = s.addRep(at(4000 + i * 1000));
      }
      expect(s.phase, RoundPhase.finished);
      expect(s.reps, 10);
      expect(s.endedAt, at(13000));
    });

    test('a target round still ends at 2 minutes', () {
      final s = running(RoundKind.r20).tick(at(3000 + 120000));
      expect(s.phase, RoundPhase.finished);
      expect(s.banked, RoundKind.maxRound);
    });

    test('steady reps earn the bonus; half and rushed reps are only noted', () {
      var s = running(RoundKind.s60)
          .onEvent(rep, at(4000))
          .onEvent(slowRep, at(6000))
          .onEvent(const HalfRep(depth: 0.5), at(7000))
          .onEvent(const TooFast(took: Duration(milliseconds: 400)), at(8000));
      expect([s.reps, s.steady, s.halfReps, s.tooFast], [2, 1, 1, 1]);
      expect(s.score, 3);
      s = s.onEvent(const FormHint(FormHintKind.moveBack), at(9000));
      expect(s.reps, 2);
    });

    test('body lost pauses the clock; resume counts down again', () {
      var s = running(RoundKind.s30).onEvent(const BodyLost(), at(13000));
      expect(s.phase, RoundPhase.paused);
      expect(s.pauseReason, PauseReason.bodyLost);
      expect(s.clock(at(60000)), const Duration(seconds: 20));
      s = s.startCountdown(at(60000)).tick(at(63000));
      expect(s.phase, RoundPhase.running);
      expect(s.startedAt, at(3000), reason: 'the first start is kept');
      expect(s.clock(at(73000)), const Duration(seconds: 10));
      expect(s.tick(at(83000)).phase, RoundPhase.finished);
    });

    test('pausing during 3-2-1 goes back to paused', () {
      final s = fresh(RoundKind.s30)
          .startCountdown(t0)
          .pause(PauseReason.background, at(1000));
      expect(s.phase, RoundPhase.paused);
      expect(s.countdownEnds, isNull);
    });

    test('manual −1 never goes below zero', () {
      var s = running(RoundKind.s60, mode: RoundMode.manual).removeRep();
      expect(s.reps, 0);
      s = s.addRep(at(4000)).addRep(at(5000)).removeRep();
      expect(s.reps, 1);
    });

    test('ending early keeps what was done', () {
      final s = running(RoundKind.s60)
          .onEvent(rep, at(5000))
          .pause(PauseReason.tap, at(10000))
          .end(at(20000));
      final r = RoundResult.of(s)!;
      expect(r.reps, 1);
      expect(r.duration, const Duration(seconds: 7));
      expect(r.startedAt, at(3000));
      expect(r.finishedAt, at(20000));
    });

    test('no result for a round that never ran', () {
      expect(RoundResult.of(fresh(RoundKind.s30)), isNull);
      expect(RoundResult.of(fresh(RoundKind.s30).end(t0)), isNull);
    });

    test('a clock going backwards never gives negative time', () {
      final s = running(RoundKind.s30);
      expect(s.elapsed(at(-5000)), Duration.zero);
      expect(s.clock(at(-5000)), const Duration(seconds: 30));
    });
  });

  test('analytics buckets', () {
    expect(
      [
        for (final n in [-3, 0, 1, 5, 6, 10, 11, 20, 21, 40, 41, 999])
          MoveAnalytics.repsBucket(n),
      ],
      [
        '0',
        '0',
        '1_5',
        '1_5',
        '6_10',
        '6_10',
        '11_20',
        '11_20',
        '21_40',
        '21_40',
        '41_plus',
        '41_plus',
      ],
    );
    expect(MoveAnalytics.durationBucket(const Duration(seconds: 29)), 'lt_30s');
    expect(MoveAnalytics.durationBucket(const Duration(seconds: 60)), '30_60s');
    expect(
      MoveAnalytics.durationBucket(const Duration(seconds: 90)),
      '60_120s',
    );
    expect(MoveAnalytics.durationBucket(const Duration(minutes: 5)), 'gt_120s');
    expect(MoveAnalytics.fpsBucket(null), isNull);
    expect(MoveAnalytics.fpsBucket(7.9), 'lt_8');
    expect(MoveAnalytics.fpsBucket(12), '8_15');
    expect(MoveAnalytics.fpsBucket(15), '15_plus');
  });

  test('analytics name the game: Stack with the camera, none by hand', () {
    expect(
      MoveAnalytics.game(MoveExerciseId.pushUps, RoundMode.camera),
      'stack',
    );
    expect(
      MoveAnalytics.game(MoveExerciseId.pushUps, RoundMode.manual),
      'none',
    );
  });
}
