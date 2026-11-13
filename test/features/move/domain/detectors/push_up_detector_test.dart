import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/move/domain/detectors/push_up_detector.dart';
import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_state.dart';
import 'package:gym_tracker/features/move/domain/move_exercises.dart';

import '../../helpers/synthetic_pose.dart';

/// Runs [frames] through a fresh detector.
({RepState state, List<RepEvent> events}) run(
  List<PoseFrame> frames, {
  PushUpDetector? detector,
}) {
  final d = detector ?? PushUpDetector();
  var state = const RepState();
  final events = <RepEvent>[];
  for (final f in frames) {
    final update = d.onFrame(f);
    state = update.state;
    events.addAll(update.events);
  }
  return (state: state, events: events);
}

int counted(List<RepEvent> events) => events.whereType<RepCounted>().length;

void main() {
  test('the registry gives a push-up detector for push-ups', () {
    final d = MoveExercises.detectorFor(MoveExerciseId.pushUps);
    expect(d, isA<PushUpDetector>());
    expect(d.exercise, MoveExerciseId.pushUps);
    expect(MoveExerciseId.fromId('push_ups'), MoveExerciseId.pushUps);
    expect(MoveExerciseId.fromId('PUSH_UPS'), isNull);
    expect(MoveExerciseId.fromId(null), isNull);
  });

  group('counts good reps', () {
    for (final view in SynthView.values) {
      test('${view.name}: 5 reps', () {
        final r = run(SynthSet.reps(5, view: view).frames());
        expect(r.state.reps, 5);
        expect(counted(r.events), 5);
        expect(
          r.state.view,
          view == SynthView.front ? PoseView.front : PoseView.side,
        );
        expect(r.events.whereType<HalfRep>(), isEmpty);
        expect(r.events.whereType<TooFast>(), isEmpty);
      });
    }

    for (final fps in [8.0, 12.0, 15.0, 30.0]) {
      test('at $fps fps', () {
        for (final view in SynthView.values) {
          final r = run(SynthSet.reps(6, view: view, fps: fps).frames());
          expect(r.state.reps, 6, reason: '${view.name} at $fps fps');
        }
      });
    }

    for (final scale in [0.6, 0.8, 1.2, 1.4]) {
      test('a body ${scale}x the usual size', () {
        for (final view in SynthView.values) {
          final r = run(SynthSet.reps(5, view: view, scale: scale).frames());
          expect(r.state.reps, 5, reason: view.name);
        }
      });
    }

    test('slow reps with a pause at the bottom', () {
      const slow = RepSpec(
        duration: Duration(milliseconds: 3200),
        bottomHold: Duration(seconds: 1),
      );
      for (final view in SynthView.values) {
        final r = run(SynthSet.reps(4, view: view, rep: slow).frames());
        expect(r.state.reps, 4, reason: view.name);
      }
    });

    test('back to back, no rest at the top', () {
      const quick = RepSpec(
        duration: Duration(milliseconds: 1100),
        restAfter: Duration.zero,
      );
      for (final view in SynthView.values) {
        final r = run(SynthSet.reps(8, view: view, rep: quick).frames());
        expect(r.state.reps, 8, reason: view.name);
      }
    });

    test('noisy landmarks (about 3 px at 640) still count exactly', () {
      for (final view in SynthView.values) {
        for (final seed in [1, 2, 3, 4, 5]) {
          final r = run(
            SynthSet.reps(6, view: view, noise: 0.004, seed: seed).frames(),
          );
          expect(r.state.reps, 6, reason: '${view.name} seed $seed');
        }
      }
    });

    test('the model skipping a quarter of the frames', () {
      for (final view in SynthView.values) {
        final r = run(
          SynthSet.reps(6, view: view, dropRate: 0.25, seed: 11).frames(),
        );
        expect(r.state.reps, 6, reason: view.name);
      }
    });

    test('a wider image (landscape phone)', () {
      final r = run(
        const SynthSet(
          reps: [RepSpec(), RepSpec(), RepSpec()],
          aspect: 1.33,
        ).frames(),
      );
      expect(r.state.reps, 3);
    });
  });

  group('does not count', () {
    test('half reps, and says so', () {
      for (final view in SynthView.values) {
        final r = run(
          SynthSet.reps(
            4,
            view: view,
            rep: const RepSpec(depth: 0.55),
          ).frames(),
        );
        expect(r.state.reps, 0, reason: view.name);
        expect(r.events.whereType<HalfRep>(), hasLength(4), reason: view.name);
      }
    });

    test('good and half reps mixed: only the good ones', () {
      const half = RepSpec(depth: 0.5);
      const full = RepSpec();
      final r = run(
        const SynthSet(reps: [full, half, full, half, full]).frames(),
      );
      expect(r.state.reps, 3);
      expect(r.events.whereType<HalfRep>(), hasLength(2));
    });

    test('reps faster than 0.7 s top to top', () {
      const rushed = RepSpec(
        duration: Duration(milliseconds: 500),
        restAfter: Duration(milliseconds: 200),
      );
      final r = run(SynthSet.reps(5, rep: rushed, fps: 30).frames());
      expect(r.state.reps, 0);
      expect(r.events.whereType<TooFast>(), isNotEmpty);
    });

    test('a set that starts at the bottom: the first rep needs the top', () {
      const set = SynthSet(reps: [RepSpec()], startAtBottom: true);
      final r = run(set.frames());
      // Rising from the bottom to the top is not a rep; the full one is.
      expect(r.state.reps, 1);
    });

    test('a plank held still', () {
      final r = run(const SynthSet(lead: Duration(seconds: 20)).frames());
      expect(r.state.reps, 0);
      expect(r.state.phase, RepPhase.ready);
    });
  });

  group('the body leaving the picture', () {
    test('pauses (body lost), keeps the count, counts again after', () {
      // Reps start at 1.5 s and take 2 s each; gone from 4.4 s to 7 s.
      const set = SynthSet(
        reps: [RepSpec(), RepSpec(), RepSpec(), RepSpec(), RepSpec()],
        gaps: [(Duration(milliseconds: 4400), Duration(seconds: 7))],
      );
      final r = run(set.frames());
      expect(r.events.whereType<BodyLost>(), hasLength(1));
      expect(r.events.whereType<BodyFound>(), hasLength(2));
      final lostAt = r.events.indexWhere((e) => e is BodyLost);
      expect(counted(r.events.take(lostAt).toList()), 1);
      // The rep cut by the gap is dropped; the others count.
      expect(r.state.reps, lessThan(5));
      expect(r.state.reps, greaterThanOrEqualTo(2));
    });

    test('nobody in the picture at all', () {
      final frames = [
        for (var i = 0; i < 150; i++)
          PoseFrame(
            at: Duration(milliseconds: i * 66),
            joints: const {},
          ),
      ];
      final r = run(frames);
      expect(r.state.phase, RepPhase.notVisible);
      expect(r.events, isEmpty);
    });
  });

  group('hints', () {
    List<FormHintKind> hints(List<RepEvent> events) => [
      for (final e in events.whereType<FormHint>()) e.kind,
    ];

    test('a good set gives no hints', () {
      for (final view in SynthView.values) {
        final r = run(SynthSet.reps(4, view: view).frames());
        expect(hints(r.events), isEmpty, reason: view.name);
      }
    });

    test('too small in the picture: move closer', () {
      final r = run(
        const SynthSet(scale: 0.4, reps: [RepSpec(), RepSpec()]).frames(),
      );
      expect(hints(r.events), contains(FormHintKind.moveCloser));
    });

    test('feet out of the picture: move back', () {
      final r = run(
        const SynthSet(shiftX: 0.3, reps: [RepSpec(), RepSpec()]).frames(),
      );
      expect(hints(r.events), contains(FormHintKind.moveBack));
      // Advice only: the reps still count (the arm is in view).
      expect(r.state.reps, 2);
    });

    test('dark room (the model unsure of everything): more light', () {
      final r = run(
        const SynthSet(likelihood: 0.35, reps: [RepSpec(), RepSpec()]).frames(),
      );
      expect(hints(r.events), contains(FormHintKind.moreLight));
      expect(r.state.reps, 0);
    });

    test('sagging hips from the side: straight body, still counted', () {
      final r = run(
        const SynthSet(
          sag: 0.2,
          reps: [RepSpec(), RepSpec(), RepSpec()],
        ).frames(),
      );
      expect(hints(r.events), contains(FormHintKind.straightBody));
      expect(r.state.reps, 3);
    });

    test('a hint is not repeated every frame', () {
      final r = run(
        const SynthSet(scale: 0.4, lead: Duration(seconds: 12)).frames(),
      );
      final n = hints(r.events).where((k) => k == FormHintKind.moveCloser);
      expect(n.length, inInclusiveRange(1, 3));
    });
  });

  group('never crashes on garbage', () {
    Landmark junk(math.Random r) {
      final pick = r.nextInt(8);
      double v() => switch (pick) {
        0 => double.nan,
        1 => double.infinity,
        2 => double.negativeInfinity,
        3 => 1e12,
        4 => -1e12,
        _ => r.nextDouble() * 3 - 1,
      };
      return Landmark(x: v(), y: v(), likelihood: v());
    }

    test('random joints, NaN, infinities, huge numbers', () {
      final random = math.Random(42);
      final frames = [
        for (var i = 0; i < 3000; i++)
          PoseFrame(
            at: Duration(milliseconds: i * 66),
            aspect: [0.75, double.nan, 0.0, -1.0, 1e9][i % 5],
            joints: {
              for (final j in PoseJoint.values)
                if (random.nextBool()) j: junk(random),
            },
          ),
      ];
      final r = run(frames);
      expect(r.state.reps, greaterThanOrEqualTo(0));
      expect(r.state.depth, inInclusiveRange(0, 1));
    });

    test('every joint in the same place (zero-length limbs)', () {
      final frames = [
        for (var i = 0; i < 100; i++)
          PoseFrame(
            at: Duration(milliseconds: i * 66),
            joints: {
              for (final j in PoseJoint.values)
                j: const Landmark(x: 0.5, y: 0.5, likelihood: 1),
            },
          ),
      ];
      expect(() => run(frames), returnsNormally);
    });

    test('frames out of order or repeated are ignored', () {
      final frames = SynthSet.reps(4).frames();
      final shuffled = [
        for (final f in frames) ...[f, f],
        ...frames.reversed.take(20),
      ];
      expect(run(shuffled).state.reps, 4);
    });

    test('a 10-minute set stays fast and exact', () {
      final set = SynthSet.reps(
        300,
        rep: const RepSpec(
          duration: Duration(milliseconds: 1500),
          restAfter: Duration(milliseconds: 500),
        ),
      );
      final frames = set.frames();
      final watch = Stopwatch()..start();
      final r = run(frames);
      watch.stop();
      expect(r.state.reps, 300);
      // About 9,000 frames; a phone gets one every 66 ms.
      expect(watch.elapsedMilliseconds, lessThan(2000));
    });
  });

  test('reset forgets the count, the view and the hints', () {
    final d = PushUpDetector();
    run(SynthSet.reps(3).frames(), detector: d);
    d.reset();
    final r = run(
      SynthSet.reps(2, view: SynthView.front).frames(),
      detector: d,
    );
    expect(r.state.reps, 2);
    expect(r.state.view, PoseView.front);
  });
}
