import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/move/data/repositories/prefs_move_local_repository.dart';
import 'package:gym_tracker/features/move/domain/entities/move_exercise.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/domain/usecases/save_move_round.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

RoundResult result(int reps) => RoundResult(
  exercise: MoveExerciseId.pushUps,
  kind: RoundKind.s60,
  mode: RoundMode.camera,
  reps: reps,
  steady: 0,
  halfReps: 0,
  duration: const Duration(seconds: 60),
  startedAt: DateTime(2026, 11, 12, 18),
  finishedAt: DateTime(2026, 11, 12, 18, 1),
);

void main() {
  late LocalWorkoutRepository repo;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
  });

  Future<List<WorkoutSession>> load() async =>
      switch (await repo.loadHistory()) {
        Success(:final value) => value,
        Failed(:final failure) => throw failure,
      };

  test('a round is its own session: one set of push-ups, reps only', () async {
    expect(await SaveMoveRound(repo)(result(26)), isA<Success<void>>());
    final s = (await load()).single;
    expect(s.dayId, WorkoutSession.moveDayId);
    expect(s.isMove, isTrue);
    expect(s.sets.single.exerciseId, 'push_ups');
    expect(s.sets.single.weight, 0);
    expect(s.sets.single.reps, 26);
    expect(s.startedAt!.isAtSameMomentAs(DateTime(2026, 11, 12, 18)), isTrue);
  });

  test('the chosen day survives a round', () async {
    await repo.saveChosenDay(const ChosenDay('day-3'));
    await SaveMoveRound(repo)(result(12));
    final chosen = await repo.loadChosenDay();
    expect((chosen as Success<ChosenDay?>).value?.dayId, 'day-3');
  });

  test('no reps: nothing is saved', () async {
    final saved = await SaveMoveRound(repo)(result(0));
    expect((saved as Failed<void>).failure, isA<ValidationFailure>());
    expect(await load(), isEmpty);
    expect(await SaveMoveRound(repo)(result(-4)), isA<Failed<void>>());
  });

  test('reps are clamped like a logged set', () async {
    await SaveMoveRound(repo)(result(100000));
    expect((await load()).single.sets.single.reps, SaveMoveRound.maxReps);
  });

  test('two rounds are two sessions', () async {
    await SaveMoveRound(repo)(result(10));
    final second = RoundResult(
      exercise: MoveExerciseId.pushUps,
      kind: RoundKind.s30,
      mode: RoundMode.manual,
      reps: 8,
      steady: 0,
      halfReps: 0,
      duration: const Duration(seconds: 30),
      startedAt: DateTime(2026, 11, 12, 18, 5),
      finishedAt: DateTime(2026, 11, 12, 18, 6),
    );
    await SaveMoveRound(repo)(second);
    expect(await load(), hasLength(2));
  });

  group(PrefsMoveLocalRepository, () {
    late PrefsMoveLocalRepository local;
    setUp(() async {
      local = PrefsMoveLocalRepository(await SharedPreferences.getInstance());
    });

    test('best per exercise and round kind', () async {
      const e = MoveExerciseId.pushUps;
      expect((await local.best(e, RoundKind.s60) as Success).value, isNull);
      expect(
        (await local.offerBest(e, RoundKind.s60, 12) as Success).value,
        isTrue,
      );
      expect(
        (await local.offerBest(e, RoundKind.s60, 10) as Success).value,
        isFalse,
      );
      expect(
        (await local.offerBest(e, RoundKind.s60, 12) as Success).value,
        isFalse,
      );
      expect(
        (await local.offerBest(e, RoundKind.s60, 20) as Success).value,
        isTrue,
      );
      expect((await local.best(e, RoundKind.s60) as Success).value, 20);
      expect((await local.best(e, RoundKind.s30) as Success).value, isNull);
    });

    test('impossible numbers are never kept or read back', () async {
      const e = MoveExerciseId.pushUps;
      expect(
        (await local.offerBest(e, RoundKind.s30, 0) as Success).value,
        isFalse,
      );
      expect(
        (await local.offerBest(e, RoundKind.s30, 5000) as Success).value,
        isFalse,
      );
      SharedPreferences.setMockInitialValues({
        PrefsMoveLocalRepository.bestKey(e, RoundKind.s30): -7,
        PrefsMoveLocalRepository.bestKey(e, RoundKind.r10): 'lots',
      });
      final hostile = PrefsMoveLocalRepository(
        await SharedPreferences.getInstance(),
      );
      expect((await hostile.best(e, RoundKind.s30) as Success).value, isNull);
      expect((await hostile.best(e, RoundKind.r10) as Success).value, isNull);
    });

    test('tip and camera flags', () async {
      const e = MoveExerciseId.pushUps;
      expect((await local.tipSeen(e) as Success).value, isFalse);
      await local.markTipSeen(e);
      expect((await local.tipSeen(e) as Success).value, isTrue);
      expect((await local.cameraAllowedBefore() as Success).value, isFalse);
      await local.markCameraAllowed();
      expect((await local.cameraAllowedBefore() as Success).value, isTrue);
    });

    test('sound is on until muted; odd stored values mean on', () async {
      expect((await local.soundOn() as Success).value, isTrue);
      await local.setSoundOn(on: false);
      expect((await local.soundOn() as Success).value, isFalse);
      await local.setSoundOn(on: true);
      expect((await local.soundOn() as Success).value, isTrue);

      for (final odd in <Object>['off', 0, 'false']) {
        SharedPreferences.setMockInitialValues({
          PrefsMoveLocalRepository.soundKey: odd,
        });
        final hostile = PrefsMoveLocalRepository(
          await SharedPreferences.getInstance(),
        );
        expect(
          (await hostile.soundOn() as Success).value,
          isTrue,
          reason: '$odd',
        );
      }
    });
  });
}
