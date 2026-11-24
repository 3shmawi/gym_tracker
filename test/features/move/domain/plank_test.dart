// Plank in Move games (docs/designs/plank_hold.md).
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/move/domain/detectors/plank_detector.dart';
import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_state.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/domain/games/hold_stack_rules.dart';
import 'package:gym_tracker/features/move/domain/games/stack_rules.dart';
import 'package:gym_tracker/features/move/domain/move_exercises.dart';

import '../helpers/plank_frames.dart';
import '../helpers/synthetic_pose.dart';

/// Every event and the last state of [frames] through a new detector.
({List<RepEvent> events, RepState state, List<RepState> states}) run(
  List<PoseFrame> frames,
) {
  final d = PlankDetector();
  final events = <RepEvent>[];
  final states = <RepState>[];
  var state = const RepState();
  for (final f in frames) {
    final u = d.onFrame(f);
    events.addAll(u.events);
    states.add(state = u.state);
  }
  return (events: events, state: state, states: states);
}

List<int> counted(List<RepEvent> events) => [
  for (final e in events)
    if (e is RepCounted) e.total,
];

const s = Duration(seconds: 1);

void main() {
  group(PlankDetector, () {
    test('a straight plank counts whole seconds, one event each', () {
      final r = run(plankFrames([(s * 6, 0)]));
      final totals = counted(r.events);
      // The view takes a moment to decide; then every second counts.
      expect(totals.length, inInclusiveRange(4, 6));
      expect(totals, [for (var i = 1; i <= totals.length; i++) i]);
      final first = r.events.whereType<RepCounted>().first;
      expect(first.took, s);
      expect(first.depth, 1);
      expect(r.state.reps, totals.length);
      expect(r.state.view, PoseView.side);
    });

    test('holding reads as ready at the top (placement: "plank held")', () {
      final r = run(plankFrames([(s * 3, 0)]));
      expect(r.state.phase, RepPhase.ready);
      expect(r.state.depth, 0);
      expect(r.state.issues, isNot(contains(FormHintKind.straightBody)));
    });

    test('from the other side too', () {
      final r = run(plankFrames([(s * 6, 0)], view: SynthView.sideRight));
      expect(counted(r.events).length, inInclusiveRange(4, 6));
    });

    test('sagging hips: no seconds, "straighten your body" after 0.5 s', () {
      final r = run(plankFrames([(s * 2, 0), (s * 3, 0.12)]));
      final before = r.states[29].reps; // after the straight 2 s
      expect(r.state.reps, before, reason: 'nothing counted while sagging');
      expect(
        r.events.whereType<FormHint>().map((h) => h.kind),
        contains(FormHintKind.straightBody),
      );
      expect(r.state.issues, contains(FormHintKind.straightBody));
      expect(r.state.phase, RepPhase.goingDown, reason: 'not ready');
    });

    test('back in line: the count goes on from where it was', () {
      final r = run(plankFrames([(s * 3, 0), (s * 2, 0.12), (s * 3, 0)]));
      final totals = counted(r.events);
      expect(totals, [for (var i = 1; i <= totals.length; i++) i]);
      expect(totals.length, inInclusiveRange(4, 6));
      expect(r.state.issues, isNot(contains(FormHintKind.straightBody)));
    });

    test('fractions are kept across a break (2.7 s + 2.7 s → 5 s)', () {
      // 0.7 s first for the view, then 2.7 s held, a break, 2.7 s held.
      final r = run(
        plankFrames([
          (const Duration(milliseconds: 3400), 0),
          (s * 2, 0.12),
          (const Duration(milliseconds: 2800), 0),
        ]),
      );
      expect(r.state.reps, inInclusiveRange(5, 6));
    });

    test('from the front: no line to judge, nothing counted', () {
      final r = run(plankFrames([(s * 6, 0)], view: SynthView.front));
      expect(counted(r.events), isEmpty);
    });

    test('leaving the picture: body lost; a stalled camera adds nothing', () {
      final frames = plankFrames([(s * 3, 0)]);
      final d = PlankDetector();
      frames.forEach(d.onFrame);
      final held = d.onFrame(frames.last).state.reps;
      // Nobody for 2 s.
      final lost = d.onFrame(
        PoseFrame(at: frames.last.at + s * 2, joints: const {}),
      );
      expect(lost.events, contains(isA<BodyLost>()));
      expect(lost.state.phase, RepPhase.notVisible);
      expect(lost.state.reps, held);
    });

    test('reset starts again from 0', () {
      final d = PlankDetector();
      plankFrames([(s * 4, 0)]).forEach(d.onFrame);
      d.reset();
      expect(d.holding, isFalse);
      final r = d.onFrame(plankFrames([(s, 0)]).first);
      expect(r.state.reps, 0);
    });

    test('garbage frames never throw', () {
      final d = PlankDetector();
      for (final f in [
        const PoseFrame(at: Duration.zero, joints: {}),
        const PoseFrame(
          at: s,
          joints: {
            PoseJoint.leftShoulder: Landmark(x: 0.5, y: 0.5, likelihood: 1),
            PoseJoint.leftHip: Landmark(x: 0.5, y: 0.5, likelihood: 1),
            PoseJoint.leftAnkle: Landmark(x: 0.5, y: 0.5, likelihood: 1),
            PoseJoint.leftElbow: Landmark(x: 0.5, y: 0.5, likelihood: 1),
          },
        ),
        const PoseFrame(at: s, joints: {}), // not newer
      ]) {
        expect(() => d.onFrame(f), returnsNormally);
      }
    });
  });

  group('hold rounds', () {
    final t0 = DateTime(2026, 11, 23, 18);
    RoundState running(RoundKind kind, {RoundMode mode = RoundMode.camera}) =>
        RoundState(
          exercise: MoveExerciseId.plank,
          kind: kind,
          mode: mode,
        ).startCountdown(t0).tick(t0.add(RoundState.countdown));
    const second = RepCounted(total: 1, took: s, depth: 1);

    test('a target ends at that many seconds held', () {
      var r = running(RoundKind.h30);
      final at = t0.add(const Duration(seconds: 10));
      for (var i = 0; i < 29; i++) {
        r = r.onEvent(second, at);
      }
      expect(r.phase, RoundPhase.running);
      r = r.onEvent(second, at);
      expect(r.phase, RoundPhase.finished);
      expect(r.reps, 30);
      expect(r.score, 30, reason: 'a second is never "steady"');
    });

    test('seconds before the round runs are not counted', () {
      const ready = RoundState(
        exercise: MoveExerciseId.plank,
        kind: RoundKind.h30,
        mode: RoundMode.camera,
      );
      expect(ready.onEvent(second, t0).reps, 0);
    });

    test('the clock shows the seconds held, not the time running', () {
      var r = running(RoundKind.hMax);
      r = r.onEvent(second, t0).onEvent(second, t0);
      expect(r.clock(t0.add(const Duration(seconds: 20))), s * 2);
    });

    test('as long as you can stops at the 2-minute cap', () {
      final r = running(RoundKind.hMax)
          .tick(t0.add(RoundState.countdown + RoundKind.maxRound));
      expect(r.phase, RoundPhase.finished);
    });

    test('without the camera, the seconds held are the time running', () {
      var r = running(RoundKind.h30, mode: RoundMode.manual);
      final start = t0.add(RoundState.countdown);
      r = r.tick(start.add(const Duration(seconds: 12, milliseconds: 600)));
      expect(r.reps, 12);
      r = r.tick(start.add(const Duration(seconds: 31)));
      expect(r.phase, RoundPhase.finished);
      expect(r.reps, 30);
      expect(r.banked, const Duration(seconds: 30));
    });

    test('ids are stable; plank rounds and defaults', () {
      expect(MoveExerciseId.fromId('plank'), MoveExerciseId.plank);
      expect(MoveExerciseId.plank.catalogExerciseId, 'plank');
      expect(MoveExercises.roundsFor(MoveExerciseId.plank), [
        RoundKind.h30,
        RoundKind.h45,
        RoundKind.h60,
        RoundKind.hMax,
      ]);
      expect(MoveExercises.defaultFor(MoveExerciseId.plank), RoundKind.h30);
      expect(MoveExercises.defaultFor(MoveExerciseId.pushUps), RoundKind.s60);
    });

    test('a link cannot pair plank with a push-up round, or the reverse', () {
      expect(MoveExercises.kindFor(MoveExerciseId.plank, 'r10'), RoundKind.h30);
      expect(
        MoveExercises.kindFor(MoveExerciseId.pushUps, 'hmax'),
        RoundKind.s60,
      );
      expect(
        MoveExercises.kindFor(MoveExerciseId.plank, 'hmax'),
        RoundKind.hMax,
      );
      for (final odd in [null, '', 'H30', '<script>', '../x']) {
        expect(MoveExercises.kindFor(MoveExerciseId.plank, odd), RoundKind.h30);
      }
    });

    test('a best is kept only for "as long as you can" among holds', () {
      expect(MoveExercises.keepsBest(RoundKind.hMax), isTrue);
      for (final k in [RoundKind.h30, RoundKind.h45, RoundKind.h60]) {
        expect(MoveExercises.keepsBest(k), isFalse, reason: k.id);
      }
      expect(MoveExercises.keepsBest(RoundKind.r10), isTrue);
    });

    test('the plank plays the tower and detects with PlankDetector', () {
      expect(
        MoveExercises.detectorFor(MoveExerciseId.plank),
        isA<PlankDetector>(),
      );
      expect(MoveExercises.gameFor(MoveExerciseId.plank).id.id, 'stack');
    });
  });

  group(HoldStackRules, () {
    const rules = HoldStackRules();
    final at = DateTime(2026, 11, 23);
    StackState hold(int seconds) {
      var state = rules.start();
      for (var i = 1; i <= seconds; i++) {
        state = rules.onEvent(
          state,
          RepCounted(total: i, took: s, depth: 1),
          at,
        );
      }
      return state;
    }

    test('one centred, steady block every 5 seconds', () {
      expect(hold(4).floors, isEmpty);
      expect(hold(5).floors, hasLength(1));
      expect(hold(14).floors, hasLength(2));
      expect(hold(25).floors, hasLength(5));
      expect(hold(25).floors.every((f) => f.steady && f.offset == 0), isTrue);
      expect(hold(25).last!.milestone, isTrue, reason: 'every 5th block');
    });

    test('hints and the body leaving change nothing', () {
      final five = hold(5);
      for (final e in const <RepEvent>[
        FormHint(FormHintKind.straightBody),
        BodyLost(),
        BodyFound(),
        HalfRep(depth: 0.5),
        TooFast(took: s),
      ]) {
        expect(rules.onEvent(five, e, at), same(five));
      }
    });
  });
}
