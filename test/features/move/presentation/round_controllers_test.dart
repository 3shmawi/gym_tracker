import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/core/screen_awake/screen_awake.dart';
import 'package:gym_tracker/features/move/data/repositories/prefs_move_local_repository.dart';
import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/move_sound_mode.dart';
import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/domain/games/stack_rules.dart';
import 'package:gym_tracker/features/move/domain/repositories/move_sounds.dart';
import 'package:gym_tracker/features/move/domain/repositories/move_voice.dart';
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

class FakeMoveSounds implements MoveSounds {
  int loads = 0;
  int reps = 0;
  int milestones = 0;
  bool disposed = false;

  @override
  Future<void> load() async => loads++;

  @override
  void rep() => reps++;

  @override
  void milestone() => milestones++;

  @override
  Future<void> dispose() async => disposed = true;
}

class FakeMoveVoice implements MoveVoice {
  new({this.available = true});

  final bool available;
  final languages = <String>[];
  final said = <int>[];
  bool disposed = false;

  @override
  Future<bool> prepare(String language) async {
    languages.add(language);
    return available;
  }

  @override
  void count(int count) => said.add(count);

  @override
  Future<void> dispose() async => disposed = true;
}

/// A test bed: a hand-moved clock, a fake camera, the real local history.
class Bed {
  new _(
    this.container,
    this.source,
    this.local,
    this.repo,
    this.awake,
    this.sounds,
    this.voice,
  );

  static Future<Bed> make({FakePoseSource? source, bool voice = false}) async {
    SharedPreferences.setMockInitialValues({});
    final repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
    final cam = source ?? FakePoseSource();
    final local = InMemoryMoveLocalRepository();
    final awake = FakeScreenAwake();
    final sounds = FakeMoveSounds();
    final speaker = FakeMoveVoice(available: voice);
    late Bed bed;
    final c = ProviderContainer(
      overrides: [
        poseSourceFactoryProvider.overrideWithValue(() => cam),
        moveClockProvider.overrideWithValue(() => bed.now),
        moveLocalRepositoryProvider.overrideWithValue(local),
        workoutRepositoryProvider.overrideWithValue(repo),
        screenAwakeProvider.overrideWithValue(awake),
        moveSoundsFactoryProvider.overrideWithValue(() => sounds),
        moveVoiceFactoryProvider.overrideWithValue(() => speaker),
        workoutFinishedHookProvider.overrideWithValue(() async {}),
      ],
    );
    addTearDown(c.dispose);
    return bed = Bed._(c, cam, local, repo, awake, sounds, speaker);
  }

  final ProviderContainer container;
  final FakePoseSource source;
  final InMemoryMoveLocalRepository local;
  final LocalWorkoutRepository repo;
  final FakeScreenAwake awake;
  final FakeMoveSounds sounds;
  final FakeMoveVoice voice;
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

      // The reps built the game, one sound each.
      final game = s().game! as StackState;
      expect(game.floors, hasLength(3));
      expect(game.score, s().round.score);
      expect(bed.sounds.loads, isPositive, reason: 'loading runs once');
      expect(bed.sounds.reps, 3);
      expect(bed.sounds.milestones, 0);

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

    test(
      'muted: the game still grows, silently, and it is remembered',
      () async {
        await c.start();
        // No voice on this phone: the default plays tones; one tap: off.
        expect(s().playing, MoveSoundMode.tones);
        await c.cycleSound();
        expect(s().playing, MoveSoundMode.off);
        expect(bed.local.sound, MoveSoundMode.off);

        play(const SynthSet(lead: Duration(seconds: 6)).frames());
        final reps = SynthSet.reps(5).frames();
        const offset = Duration(seconds: 7);
        play([
          for (final f in reps)
            PoseFrame(at: f.at + offset, joints: f.joints, aspect: f.aspect),
        ]);
        expect((s().game! as StackState).floors, hasLength(5));
        expect(bed.sounds.reps + bed.sounds.milestones, 0);

        // Off → (no voice) tones.
        await c.cycleSound();
        expect(bed.local.sound, MoveSoundMode.tones);
      },
    );

    test('a saved "off" is read when the camera starts', () async {
      bed.local.sound = MoveSoundMode.off;
      await c.start();
      expect(s().playing, MoveSoundMode.off);
      expect(bed.sounds.loads, 0);
      expect(bed.voice.languages, isEmpty, reason: 'no voice asked for');
    });

    test('the fifth block plays the other sound; closing frees them', () async {
      await c.start();
      play(const SynthSet(lead: Duration(seconds: 6)).frames());
      final reps = SynthSet.reps(5).frames();
      const offset = Duration(seconds: 7);
      play([
        for (final f in reps)
          PoseFrame(at: f.at + offset, joints: f.joints, aspect: f.aspect),
      ]);
      expect(bed.sounds.reps, 4);
      expect(bed.sounds.milestones, 1);
      bed.container.dispose();
      await pumpEventQueue();
      expect(bed.sounds.disposed, isTrue);
    });

    test(
      'the nothing-played-before-running rule holds for the voice',
      () async {
        await c.start(language: 'ar');
        play(SynthSet.reps(2).frames());
        expect(bed.voice.said, isEmpty);
      },
    );

    test('nothing done before the round runs reaches the game', () async {
      await c.start();
      // Reps during placement (before 3-2-1 ends) build nothing.
      play(SynthSet.reps(2).frames());
      expect((s().game! as StackState).floors, isEmpty);
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

  group('spoken count', () {
    late Bed bed;
    late CameraRoundController c;
    CameraRoundState s() =>
        bed.container.read(cameraRoundControllerProvider(launch));

    setUp(() async {
      bed = await Bed.make(voice: true);
      bed.container.listen(cameraRoundControllerProvider(launch), (_, _) {});
      c = bed.container.read(cameraRoundControllerProvider(launch).notifier);
    });

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

    Future<void> placeAndDo(int reps) async {
      play(const SynthSet(lead: Duration(seconds: 6)).frames());
      final frames = SynthSet.reps(reps).frames();
      const offset = Duration(seconds: 7);
      play([
        for (final f in frames)
          PoseFrame(at: f.at + offset, joints: f.joints, aspect: f.aspect),
      ]);
    }

    test(
      "each rep is said out loud, in the app's language, no tones",
      () async {
        await c.start(language: 'ar');
        await pumpEventQueue();
        expect(bed.voice.languages, ['ar']);
        expect(s().voiceReady, isTrue);
        expect(s().playing, MoveSoundMode.voice);
        await placeAndDo(6);
        expect(bed.voice.said, [1, 2, 3, 4, 5, 6]);
        expect(bed.sounds.reps + bed.sounds.milestones, 0);
      },
    );

    test('the button goes voice → tones → off → voice, remembered', () async {
      await c.start(language: 'en');
      await pumpEventQueue();
      final seen = <MoveSoundMode>[];
      for (var i = 0; i < 3; i++) {
        await c.cycleSound();
        seen.add(bed.local.sound);
      }
      expect(seen, [
        MoveSoundMode.tones,
        MoveSoundMode.off,
        MoveSoundMode.voice,
      ]);
    });

    test('tones mode with a voice available plays tones only', () async {
      bed.local.sound = MoveSoundMode.tones;
      await c.start(language: 'en');
      await pumpEventQueue();
      await placeAndDo(3);
      expect(bed.voice.said, isEmpty);
      expect(bed.sounds.reps, 3);
    });

    test('the voice is asked for once, even after a pause', () async {
      await c.start(language: 'en');
      await pumpEventQueue();
      await c.background();
      await c.start(language: 'en');
      await pumpEventQueue();
      expect(bed.voice.languages, ['en']);
    });

    test('closing the round frees the voice', () async {
      await c.start(language: 'en');
      bed.container.dispose();
      await pumpEventQueue();
      expect(bed.voice.disposed, isTrue);
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
