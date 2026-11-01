import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_draft.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fails loading the plan [failuresLeft] times, then delegates.
class _FlakyRepo implements WorkoutRepository {
  new(this._inner);

  final WorkoutRepository _inner;
  int failuresLeft = 1;

  @override
  Future<Result<WorkoutPlan?>> loadPlan() async {
    if (failuresLeft > 0) {
      failuresLeft--;
      return const Failed(NetworkFailure());
    }
    return await _inner.loadPlan();
  }

  @override
  Future<Result<List<WorkoutSession>>> loadHistory() => _inner.loadHistory();

  @override
  Future<Result<void>> savePlan(WorkoutPlan plan) => _inner.savePlan(plan);

  @override
  Future<Result<void>> saveSession(WorkoutSession s) => _inner.saveSession(s);

  @override
  Future<Result<int?>> loadChosenDay() => _inner.loadChosenDay();

  @override
  Future<Result<Level>> loadBestLevel() => _inner.loadBestLevel();

  @override
  Future<Result<void>> saveBestLevel(Level level) =>
      _inner.saveBestLevel(level);

  @override
  Future<Result<WorkoutDraft?>> loadDraft() => _inner.loadDraft();

  @override
  Future<Result<void>> saveDraft(WorkoutDraft? d) => _inner.saveDraft(d);

  @override
  Future<Result<void>> saveChosenDay(int? d) => _inner.saveChosenDay(d);
}

void main() {
  late WorkoutRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
  });

  ProviderContainer container(WorkoutRepository r) {
    final c = ProviderContainer(
      overrides: [
        workoutRepositoryProvider.overrideWithValue(r),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 5)),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('no plan → null (empty state)', () async {
    final c = container(repo);
    expect(await c.read(nextWorkoutControllerProvider.future), isNull);
  });

  test('using the template saves it and shows day 1', () async {
    final c = container(repo);
    await c.read(nextWorkoutControllerProvider.future);
    await c.read(nextWorkoutControllerProvider.notifier).useTemplate();
    final next = c.read(nextWorkoutControllerProvider).value!;
    expect(next.dayIndex, 0);
    expect(next.day.name.en, 'Chest & Back');
    expect((await repo.loadPlan() as Success).value, isNotNull);
  });

  test('a failure becomes an error with the AppFailure', () async {
    final c = container(_FlakyRepo(repo));
    await expectLater(
      c.read(nextWorkoutControllerProvider.future),
      throwsA(isA<NetworkFailure>()),
    );
    expect(c.read(nextWorkoutControllerProvider).error, isA<NetworkFailure>());
  });

  test('retry recovers after a failure', () async {
    final c = container(_FlakyRepo(repo));
    await c.read(nextWorkoutControllerProvider.future).catchError((_) => null);
    await c.read(nextWorkoutControllerProvider.notifier).retry();
    final state = c.read(nextWorkoutControllerProvider);
    expect(state.hasError, isFalse);
    expect(state.value, isNull);
  });

  test('the missed-day banner follows the clock', () async {
    await repo.savePlan(
      const WorkoutPlan(
        days: [
          WorkoutDay(
            name: LocalizedName(ar: 'أ', en: 'A'),
            exercises: [],
          ),
          WorkoutDay(
            name: LocalizedName(ar: 'ب', en: 'B'),
            exercises: [],
          ),
        ],
      ),
    );
    await repo.saveSession(
      WorkoutSession(
        dayIndex: 0,
        finishedAt: DateTime(2026, 11, 2, 19),
        sets: const [],
      ),
    );
    final next = await container(repo)
        .read(nextWorkoutControllerProvider.future);
    expect(next!.day.name.en, 'B');
    expect(next.waitingSince, DateTime(2026, 11, 3));
  });

  test('choosing a day makes it next until a workout is finished', () async {
    final c = container(repo);
    await c.read(nextWorkoutControllerProvider.future);
    final controller = c.read(nextWorkoutControllerProvider.notifier);
    await controller.useTemplate();
    await controller.chooseDay(2);
    expect(c.read(nextWorkoutControllerProvider).value!.day.name.en, 'Legs');

    // Finishing day 3 clears the choice; the plan continues with day 4.
    await repo.saveSession(
      WorkoutSession(
        dayIndex: 2,
        finishedAt: DateTime(2026, 11, 2),
        sets: const [],
      ),
    );
    c.invalidate(nextWorkoutControllerProvider);
    final next = await c.read(nextWorkoutControllerProvider.future);
    expect(next!.dayIndex, 3);
  });

  test('trained today, unless a workout is in progress', () async {
    // The clock says 5 Nov 2026.
    ok(await repo.savePlan(PlanTemplates.fiveDaySplit));
    ok(
      await repo.saveSession(
        WorkoutSession(
          dayIndex: 0,
          finishedAt: DateTime(2026, 11, 5, 7),
          sets: const [],
        ),
      ),
    );
    final before = await container(repo)
        .read(nextWorkoutControllerProvider.future);
    expect(before!.trainedToday, isTrue);

    ok(
      await repo.saveDraft(
        WorkoutDraft(dayIndex: 1, startedAt: DateTime(2026, 11, 5, 18)),
      ),
    );
    final during = await container(repo)
        .read(nextWorkoutControllerProvider.future);
    expect(during!.trainedToday, isFalse);
  });

  group('level', () {
    /// Three workouts a week for [weeks] weeks, ending the week before the
    /// clock (5 Nov 2026).
    Future<void> train(int weeks) async {
      ok(await repo.savePlan(PlanTemplates.fiveDaySplit));
      final start = DateTime(2026, 10, 31).subtract(Duration(days: weeks * 7));
      for (var w = 0; w < weeks; w++) {
        for (var d = 0; d < 3; d++) {
          ok(
            await repo.saveSession(
              WorkoutSession(
                dayIndex: d,
                finishedAt: start.add(Duration(days: w * 7 + d, hours: 18)),
                sets: const [],
              ),
            ),
          );
        }
      }
    }

    test('starts as a beginner', () async {
      ok(await repo.savePlan(PlanTemplates.fiveDaySplit));
      final next = await container(repo)
          .read(nextWorkoutControllerProvider.future);
      expect(next!.level.level, Level.beginner);
      expect(ok(await repo.loadBestLevel()), Level.beginner);
    });

    test('a new best level is saved', () async {
      await train(4);
      final next = await container(repo)
          .read(nextWorkoutControllerProvider.future);
      expect(next!.level.level, Level.intermediate);
      expect(next.level.streakWeeks, 4);
      expect(ok(await repo.loadBestLevel()), Level.intermediate);
    });

    test('the stored best level makes the comeback fast', () async {
      await train(1);
      ok(await repo.saveBestLevel(Level.pro));
      final next = await container(repo)
          .read(nextWorkoutControllerProvider.future);
      expect(next!.level.level, Level.beginner);
      expect(next.level.comeback, isTrue);
      expect(next.level.weeksToNext, 1);
      expect(ok(await repo.loadBestLevel()), Level.pro);
    });
  });
}

T ok<T>(Result<T> r) => switch (r) {
  Success(:final value) => value,
  Failed(:final failure) => fail('expected success, got $failure'),
};
