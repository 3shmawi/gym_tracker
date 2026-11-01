import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_draft.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/presentation/active_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

T ok<T>(Result<T> r) => (r as Success<T>).value;

void main() {
  late LocalWorkoutRepository repo;
  var now = DateTime(2026, 11, 2, 18);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
    now = DateTime(2026, 11, 2, 18);
    await repo.savePlan(PlanTemplates.fiveDaySplit);
    await repo.saveSession(
      WorkoutSession(
        dayIndex: 4,
        finishedAt: DateTime(2026, 10, 30),
        sets: [
          for (var i = 0; i < 3; i++)
            const LoggedSet(
              exerciseId: 'wide_lat_pulldown',
              weight: 50,
              reps: 12,
            ),
        ],
      ),
    );
  });

  Future<ProviderContainer> start(int day) async {
    await repo.saveDraft(WorkoutDraft(dayIndex: day, startedAt: now));
    final c = ProviderContainer(
      overrides: [
        workoutRepositoryProvider.overrideWithValue(repo),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(c.dispose);
    await c.read(activeWorkoutControllerProvider.future);
    return c;
  }

  ActiveWorkout state(ProviderContainer c) =>
      c.read(activeWorkoutControllerProvider).value!;
  ActiveWorkoutController ctl(ProviderContainer c) =>
      c.read(activeWorkoutControllerProvider.notifier);

  test('no draft → null', () async {
    final c = ProviderContainer(
      overrides: [workoutRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    expect(await c.read(activeWorkoutControllerProvider.future), isNull);
  });

  test(
    'a draft for a day the plan no longer has → null, not a crash',
    () async {
      await repo.saveDraft(WorkoutDraft(dayIndex: 99, startedAt: now));
      final c = ProviderContainer(
        overrides: [workoutRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(c.dispose);
      expect(await c.read(activeWorkoutControllerProvider.future), isNull);
    },
  );

  test('logging saves the set, starts the rest and moves to set 2', () async {
    final c = await start(0);
    expect(state(c).cursor!.exerciseIndex, 0);
    await ctl(c).logSet(weight: 22.5, reps: 12);

    final s = state(c);
    expect(s.draft.sets.single.weight, 22.5);
    expect(s.draft.restEndsAt, now.add(const Duration(seconds: 90)));
    expect((s.cursor!.exerciseIndex, s.cursor!.setNumber), (0, 2));
    // Saved to the phone right away.
    expect(ok(await repo.loadDraft())!.sets, hasLength(1));
  });

  test('the second exercise is prefilled with the suggestion', () async {
    final c = await start(0);
    for (var i = 0; i < 3; i++) {
      await ctl(c).logSet(weight: 22.5, reps: 12);
    }
    final cursor = state(c).cursor!;
    expect(cursor.exerciseIndex, 1);
    expect(cursor.weight, 52.5, reason: '50×12 ×3 last time → 52.5');
  });

  test('+15 s and skip change the rest', () async {
    final c = await start(0);
    await ctl(c).logSet(weight: 20, reps: 12);
    await ctl(c).addRest(const Duration(seconds: 15));
    expect(state(c).draft.restEndsAt, now.add(const Duration(seconds: 105)));
    await ctl(c).endRest();
    expect(state(c).draft.restEndsAt, isNull);
  });

  test('superset: no rest after A, rest after B (day 2)', () async {
    final c = await start(1);
    for (var i = 0; i < 12; i++) {
      await ctl(c).logSet(weight: 10, reps: 12);
      await ctl(c).endRest();
    }
    expect(state(c).cursor!.exerciseIndex, 4);
    await ctl(c).logSet(weight: 12.5, reps: 12);
    expect(state(c).draft.restEndsAt, isNull, reason: 'straight to B');
    expect(state(c).cursor!.exerciseIndex, 5);
    await ctl(c).logSet(weight: 15, reps: 12);
    expect(state(c).draft.restEndsAt, isNotNull, reason: 'rest after B');
    expect(state(c).cursor!.exerciseIndex, 4);
  });

  test('edit and delete a logged set', () async {
    final c = await start(0);
    await ctl(c).logSet(weight: 22.5, reps: 12);
    await ctl(c).editSet(0, weight: 25, reps: 10);
    expect(state(c).draft.sets.single.weight, 25);
    expect(state(c).draft.sets.single.reps, 10);
    await ctl(c).deleteSet(0);
    expect(state(c).draft.sets, isEmpty);
    expect(state(c).cursor!.setNumber, 1);
  });

  test('out-of-range edits and deletes are ignored', () async {
    final c = await start(0);
    await ctl(c).logSet(weight: 20, reps: 12);
    await ctl(c).editSet(5, weight: 1, reps: 1);
    await ctl(c).deleteSet(-1);
    expect(state(c).draft.sets.single.weight, 20);
  });

  test('hostile numbers are clamped, never stored as-is', () async {
    final c = await start(0);
    await ctl(c).logSet(weight: double.nan, reps: -5);
    await ctl(c).logSet(weight: 1000000000, reps: 100000);
    await ctl(c).logSet(weight: double.infinity, reps: 12);
    final sets = state(c).draft.sets;
    expect(sets[0].weight, 0);
    expect(sets[0].reps, 0);
    expect(sets[1].weight, ActiveWorkoutController.maxWeight);
    expect(sets[1].reps, ActiveWorkoutController.maxReps);
    expect(sets[2].weight, 0);
  });

  test('a restarted app resumes where it was', () async {
    final c = await start(0);
    await ctl(c).logSet(weight: 22.5, reps: 12);
    final again = ProviderContainer(
      overrides: [
        workoutRepositoryProvider.overrideWithValue(repo),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(again.dispose);
    final resumed = await again.read(activeWorkoutControllerProvider.future);
    expect(resumed!.draft.sets, hasLength(1));
    expect(resumed.cursor!.setNumber, 2);
    expect(resumed.draft.restEndsAt, isNotNull);
  });

  test('finish saves the workout, clears the draft and advances', () async {
    final c = await start(0);
    await ctl(c).logSet(weight: 52.5, reps: 12);
    now = now.add(const Duration(minutes: 50));
    expect(await ctl(c).finish(), isTrue);

    expect(c.read(activeWorkoutControllerProvider).value, isNull);
    expect(ok(await repo.loadDraft()), isNull);
    final history = ok(await repo.loadHistory());
    expect(history.last.dayIndex, 0);
    expect(history.last.sets.single.weight, 52.5);
    expect(history.last.finishedAt.isAtSameMomentAs(now), isTrue);

    final next = await c.read(nextWorkoutControllerProvider.future);
    expect(next!.dayIndex, 1);
  });

  test('summary counts a heavier pulldown as a record', () async {
    final c = await start(0);
    for (var i = 0; i < 3; i++) {
      await ctl(c).logSet(weight: 22.5, reps: 12);
    }
    await ctl(c).logSet(weight: 52.5, reps: 12);
    final summary = state(c).summary;
    expect(summary.sets, 4);
    expect(summary.records.single.exerciseId, 'wide_lat_pulldown');
  });

  test('the last set of the day starts no rest', () async {
    final c = await start(0);
    final total = state(c).plannedSets;
    for (var i = 0; i < total; i++) {
      await ctl(c).logSet(weight: 10, reps: 12);
      if (i < total - 1) await ctl(c).endRest();
    }
    expect(state(c).cursor, isNull);
    expect(state(c).draft.restEndsAt, isNull);
  });
}
