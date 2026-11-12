import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/core/screen_awake/screen_awake.dart';
import 'package:gym_tracker/features/move/data/repositories/prefs_move_local_repository.dart';
import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/domain/repositories/pose_source.dart';
import 'package:gym_tracker/features/move/presentation/camera_round_controller.dart';
import 'package:gym_tracker/features/move/presentation/manual_round_controller.dart';
import 'package:gym_tracker/features/move/presentation/move_check_controller.dart';
import 'package:gym_tracker/features/move/presentation/move_providers.dart';
import 'package:gym_tracker/features/move/presentation/round_outcome.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/fake_pose_source.dart';
import '../helpers/synthetic_pose.dart';

class FakeScreenAwake implements ScreenAwake {
  final calls = <bool>[];
  @override
  Future<void> keepOn({required bool on}) async => calls.add(on);
}

/// A test bed: a hand-moved clock, a fake camera, the real local history.
class Bed {
  new _(this.container, this.source, this.local, this.repo, this.awake);

  static Future<Bed> make({FakePoseSource? source}) async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
    final cam = source ?? FakePoseSource();
    final local = InMemoryMoveLocalRepository();
    final awake = FakeScreenAwake();
    late Bed bed;
    final c = ProviderContainer(
      overrides: [
        poseSourceFactoryProvider.overrideWithValue(() => cam),
        moveClockProvider.overrideWithValue(() => bed.now),
        moveLocalRepositoryProvider.overrideWithValue(local),
        workoutRepositoryProvider.overrideWithValue(repo),
        screenAwakeProvider.overrideWithValue(awake),
        workoutFinishedHookProvider.overrideWithValue(() async {}),
      ],
    );
    addTearDown(c.dispose);
    return bed = Bed._(c, cam, local, repo, awake);
  }

  final ProviderContainer container;
  final FakePoseSource source;
  final InMemoryMoveLocalRepository local;
  final LocalWorkoutRepository repo;
  final FakeScreenAwake awake;
  DateTime now = DateTime(2026, 11, 12, 18);

  Future<List<WorkoutSession>> history() async =>
      switch (await repo.loadHistory()) {
        Success(:final value) => value,
        Failed(:final failure) => throw failure,
      };
}

const launch = MoveLaunch(MoveExerciseId.pushUps, RoundKind.s30);

void main() {
  group(CameraRoundController, () {
    late Bed bed;
    late CameraRoundController c;
    CameraRoundState s() =>
        bed.container.read(cameraRoundControllerProvider(launch));

    setUp(() async {
      bed = await Bed.make();
      bed.container.listen(cameraRoundControllerProvider(launch), (_, _) {});
      c = bed.container.read(cameraRoundControllerProvider(launch).notifier);
    });

    /// Plays [frames] as if they came live, starting at the current time.
    void play(List<PoseFrame> frames) {
      final base = bed.now;
      for (final f in frames) {
        bed.now = base.add(f.at);
        bed.source.emit(
          PoseFrame(at: f.at, joints: f.joints, aspect: f.aspect),
        );
        c.tick();
      }
    }

    test('nothing starts until the screen asks: no camera on create', () {
      expect(bed.source.starts, 0);
      expect(s().stage, CameraStage.starting);
    });

    test('placement → 3-2-1 → round → results → saved', () async {
      await c.start();
      expect(s().stage, CameraStage.placement);
      expect(s().cameraOn, isTrue);
      expect(bed.awake.calls, [true]);
      expect(bed.local.camera, isTrue, reason: 'the why screen is skipped');

      // Hold the plank until placement is green, then 3-2-1.
      play(const SynthSet(lead: Duration(seconds: 6)).frames());
      expect(s().stage, CameraStage.live);
      expect(s().round.phase, RoundPhase.running);

      // Three reps (the detector keeps counting from the same timeline).
      final reps = SynthSet.reps(3).frames();
      const offset = Duration(seconds: 7);
      play([
        for (final f in reps)
          PoseFrame(at: f.at + offset, joints: f.joints, aspect: f.aspect),
      ]);
      expect(s().round.reps, 3);

      // Time runs out.
      bed.now = bed.now.add(const Duration(seconds: 40));
      c.tick();
      await pumpEventQueue();
      expect(s().round.phase, RoundPhase.finished);
      expect(s().cameraOn, isFalse);
      expect(bed.source.stops, 1);
      expect(bed.awake.calls.last, isFalse);
      final outcome = s().outcome!;
      expect(outcome.result.reps, 3);
      expect(outcome.result.mode, RoundMode.camera);
      expect(outcome.newBest, isTrue);

      await c.save();
      expect(s().outcome!.save, SaveState.saved);
      final saved = (await bed.history()).single;
      expect(saved.isMove, isTrue);
      expect(saved.sets.single.reps, 3);
    });

    test('a refused camera: the denied screen, nothing left running', () async {
      bed.source.startsAs = const PoseSourceStatus(
        PoseSourceState.failed,
        problem: PoseProblem.denied,
      );
      await c.start();
      expect(s().stage, CameraStage.failed);
      expect(s().trouble, CameraTrouble.denied);
      expect(bed.source.stops, 1);
      expect(bed.local.camera, isFalse);
    });

    test('a phone too slow for the model offers counting by hand', () async {
      await c.start();
      bed.source.setStatus(
        const PoseSourceStatus(PoseSourceState.running, fps: 5),
      );
      bed.now = bed.now.add(const Duration(seconds: 5));
      c.tick();
      await pumpEventQueue();
      expect(s().stage, CameraStage.failed);
      expect(s().trouble, CameraTrouble.tooSlow);
    });

    test(
      'leaving the app pauses and releases the camera; resume restarts',
      () async {
        await c.start();
        play(const SynthSet(lead: Duration(seconds: 6)).frames());
        expect(s().round.phase, RoundPhase.running);
        await c.background();
        expect(s().round.phase, RoundPhase.paused);
        expect(s().round.pauseReason, PauseReason.background);
        expect(bed.source.stops, 1);
        expect(s().cameraOn, isFalse);
        await c.resume();
        expect(bed.source.starts, 2);
        expect(s().round.phase, RoundPhase.countdown);
      },
    );

    test('the body leaving pauses; coming back counts down again', () async {
      await c.start();
      play(const SynthSet(lead: Duration(seconds: 6)).frames());
      play(
        const SynthSet(
              lead: Duration(seconds: 4),
              gaps: [(Duration.zero, Duration(seconds: 2))],
            )
            .frames()
            .map(
              (f) => PoseFrame(
                at: f.at + const Duration(seconds: 7),
                joints: f.joints,
              ),
            )
            .toList(),
      );
      // Lost, then found again: back in 3-2-1 or running.
      expect(s().round.phase, anyOf(RoundPhase.countdown, RoundPhase.running));
    });

    test('ending early still gives results; 0 reps cannot be saved', () async {
      await c.start();
      play(const SynthSet(lead: Duration(seconds: 6)).frames());
      c.end();
      await pumpEventQueue();
      final outcome = s().outcome!;
      expect(outcome.result.reps, 0);
      expect(outcome.canSave, isFalse);
      await c.save();
      expect(await bed.history(), isEmpty);
    });
  });

  group(ManualRoundController, () {
    late Bed bed;
    late ManualRoundController c;
    ManualRoundState s() =>
        bed.container.read(manualRoundControllerProvider(launch));

    setUp(() async {
      bed = await Bed.make();
      bed.container.listen(manualRoundControllerProvider(launch), (_, _) {});
      c = bed.container.read(manualRoundControllerProvider(launch).notifier);
    });

    test('taps count only while running; −1 fixes a mistake', () async {
      c.tap();
      expect(s().round.reps, 0);
      c.start();
      expect(s().round.phase, RoundPhase.countdown);
      bed.now = bed.now.add(const Duration(seconds: 3));
      c.tick();
      expect(s().round.phase, RoundPhase.running);
      for (var i = 0; i < 5; i++) {
        c.tap();
      }
      c.undo();
      expect(s().round.reps, 4);
      c.end();
      await pumpEventQueue();
      expect(s().outcome!.result.reps, 4);
      expect(s().outcome!.result.mode, RoundMode.manual);
      await c.save();
      expect(s().outcome!.save, SaveState.saved);
      expect((await bed.history()).single.sets.single.reps, 4);
      // No camera at all.
      expect(bed.source.starts, 0);
    });

    test('a timed round ends on time by itself', () async {
      c.start();
      bed.now = bed.now.add(const Duration(seconds: 3));
      c
        ..tick()
        ..tap();
      bed.now = bed.now.add(const Duration(seconds: 31));
      c.tick();
      await pumpEventQueue();
      expect(s().round.phase, RoundPhase.finished);
      expect(s().outcome!.result.duration, const Duration(seconds: 30));
    });

    test('pause and background stop the clock', () {
      c.start();
      bed.now = bed.now.add(const Duration(seconds: 3));
      c.tick();
      bed.now = bed.now.add(const Duration(seconds: 10));
      c.background();
      expect(s().round.phase, RoundPhase.paused);
      bed.now = bed.now.add(const Duration(minutes: 5));
      expect(s().round.clock(bed.now), const Duration(seconds: 20));
      c.resume();
      expect(s().round.phase, RoundPhase.countdown);
    });

    test('saving twice saves once', () async {
      c.start();
      bed.now = bed.now.add(const Duration(seconds: 3));
      c
        ..tick()
        ..tap()
        ..end();
      await pumpEventQueue();
      await c.save();
      await c.save();
      expect(await bed.history(), hasLength(1));
    });
  });
}
