import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout.dart';
import 'package:gym_tracker/features/workout/domain/usecases/suggest_next_weight.dart';
import 'package:gym_tracker/features/workout/presentation/workout_controller.dart';

import '../../../helpers/workout_fakes.dart';

void main() {
  late FakeWorkoutRepository repo;
  late ProviderContainer container;

  WorkoutController controller() =>
      container.read(workoutControllerProvider.notifier);
  Future<WorkoutState> state() =>
      container.read(workoutControllerProvider.future);

  void createContainer(FakeWorkoutRepository fake) {
    repo = fake;
    container = ProviderContainer(
      overrides: [workoutRepositoryProvider.overrideWithValue(fake)],
    );
    addTearDown(container.dispose);
    // Keep the provider alive like a mounted screen does.
    container.listen(workoutControllerProvider, (_, _) {});
  }

  setUp(() => createContainer(FakeWorkoutRepository(plan: testPlan)));

  test('shows the next day of the plan', () async {
    final s = await state();
    expect(s.day?.id, 'd1');
    expect(s.isActive, isFalse);
  });

  test('suggests the next weight from the last session', () async {
    repo.last['bench'] = [
      for (var i = 1; i <= 3; i++)
        LoggedSet(
          id: 'l$i',
          sessionId: 'old',
          exerciseId: 'bench',
          setNumber: i,
          weightKg: 40,
          reps: 10,
          loggedAt: DateTime(2026),
        ),
    ];
    final s = await state();
    expect(
      s.suggestionFor(testPlan.days.first.exercises.first),
      const WeightSuggestion(trend: WeightTrend.increase, weightKg: 42.5),
    );
  });

  test('start, log sets and complete moves to the next day', () async {
    await state();
    await controller().start();
    final bench = testPlan.days.first.exercises.first;

    await controller().logSet(bench, weightKg: 40, reps: 10);
    await controller().logSet(bench, weightKg: 40, reps: 9);
    var s = await state();
    expect(s.setsFor('bench').map((x) => x.setNumber), [1, 2]);
    expect(repo.syncCalls, 2, reason: 'each set is pushed when online');

    final next = await controller().complete();
    s = await state();
    expect(next?.id, 'd2');
    expect(s.day?.id, 'd2');
    expect(s.isActive, isFalse);
  });

  test('deleting a set removes it', () async {
    await state();
    await controller().start();
    final set = await controller().logSet(
      testPlan.days.first.exercises.first,
      weightKg: 40,
      reps: 10,
    );
    await controller().deleteSet(set!);
    expect((await state()).sessionSets, isEmpty);
  });

  test('first launch offline shows an error', () async {
    createContainer(
      FakeWorkoutRepository(refreshResult: const Failed(NetworkFailure())),
    );

    await expectLater(state(), throwsA(isA<NetworkFailure>()));
  });

  test('a failed refresh keeps the cached plan on screen', () async {
    await state();
    repo.refreshResult = const Failed(NetworkFailure());
    await controller().refresh();
    final s = await state();
    expect(s.plan?.planId, 'plan');
    expect(s.refreshFailure, isA<NetworkFailure>());
  });

  test('no plan: empty state', () async {
    createContainer(FakeWorkoutRepository());
    expect((await state()).day, isNull);
  });
}
