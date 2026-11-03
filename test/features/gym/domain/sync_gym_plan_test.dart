import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_plan.dart';
import 'package:gym_tracker/features/gym/domain/usecases/sync_gym_plan.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_draft.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/plan_sync_fakes.dart';

void main() {
  late FakePlanServer server;
  late MemoryPlanStore store;
  late LocalWorkoutRepository workouts;
  final now = DateTime.utc(2026, 11, 3, 10);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    workouts = LocalWorkoutRepository(await SharedPreferences.getInstance());
    server = FakePlanServer();
    store = MemoryPlanStore();
  });

  SyncGymPlan sync() => SyncGymPlan(server, store, workouts, now: () => now);

  PlanSyncOutcome outcome(Result<PlanSyncOutcome> r) =>
      (r as Success<PlanSyncOutcome>).value;

  test(
    'the first plan is stored, with no toast (nothing changed for them)',
    () async {
      server.plan = gymPlan(updatedBy: 'captain');
      final o = outcome(await sync()('m1'));
      expect(o.replaced, isTrue);
      expect(o.toast, isFalse);
      expect(store.data['m1']!.version, 1);
    },
  );

  test(
    'a captain change replaces the local plan and shows the toast once',
    () async {
      store.data['m1'] = const StoredGymPlan(
        plan: PlanTemplates.fiveDaySplit,
        version: 1,
        seenVersion: 1,
      );
      server.plan = gymPlan(
        version: 2,
        updatedBy: 'captain',
        plan: renamedDay1(),
      );
      final o = outcome(await sync()('m1'));
      expect(o.replaced, isTrue);
      expect(o.toast, isTrue);
      expect(store.data['m1']!.plan.days.first.name.en, 'Renamed');
      expect(store.data['m1']!.seenVersion, 2);
      // The same version again: nothing, and no second toast.
      final again = outcome(await sync()('m1'));
      expect(again.replaced, isFalse);
      expect(again.toast, isFalse);
    },
  );

  test('my own change coming back is not announced', () async {
    store.data['m1'] = const StoredGymPlan(
      plan: PlanTemplates.fiveDaySplit,
      version: 1,
      seenVersion: 1,
    );
    server.plan = gymPlan(version: 2, updatedBy: 'm1', plan: renamedDay1());
    final o = outcome(await sync()('m1'));
    expect(o.replaced, isTrue);
    expect(o.toast, isFalse);
  });

  test('an older or equal version never replaces a newer local plan', () async {
    store.data['m1'] = StoredGymPlan(plan: renamedDay1(), version: 5);
    for (final v in [1, 4, 5]) {
      server.plan = gymPlan(version: v, updatedBy: 'captain');
      expect(outcome(await sync()('m1')).replaced, isFalse, reason: '$v');
    }
    expect(store.data['m1']!.plan.days.first.name.en, 'Renamed');
  });

  test(
    'the waiting workout stays the same after the captain reorders days',
    () async {
      await workouts.savePlan(PlanTemplates.fiveDaySplit);
      final days = PlanTemplates.fiveDaySplit.days;
      await workouts.saveSession(
        WorkoutSession(
          dayId: days[0].id,
          finishedAt: now.subtract(const Duration(days: 1)),
          sets: const [],
        ),
      );
      store.data['m1'] = const StoredGymPlan(
        plan: PlanTemplates.fiveDaySplit,
        version: 1,
      );
      // Day 3 is put before day 2: by the history alone day 3 would now wait,
      // but the member was about to do day 2.
      server.plan = gymPlan(
        version: 2,
        updatedBy: 'captain',
        plan: WorkoutPlan(days: [days[0], days[2], days[1], ...days.skip(3)]),
      );
      await sync()('m1');
      final chosen =
          (await workouts.loadChosenDay() as Success<ChosenDay?>).value;
      expect(chosen?.dayId, days[1].id);
      expect(chosen?.byEdit, isTrue);
    },
  );

  test(
    'when the waiting day is deleted, the next one after it waits',
    () async {
      await workouts.savePlan(PlanTemplates.fiveDaySplit);
      final days = PlanTemplates.fiveDaySplit.days;
      await workouts.saveSession(
        WorkoutSession(
          dayId: days[0].id,
          finishedAt: now.subtract(const Duration(days: 1)),
          sets: const [],
        ),
      );
      store.data['m1'] = const StoredGymPlan(
        plan: PlanTemplates.fiveDaySplit,
        version: 1,
      );
      server.plan = gymPlan(
        version: 2,
        updatedBy: 'captain',
        plan: planWithout(PlanTemplates.fiveDaySplit, days[1].id),
      );
      await sync()('m1');
      // The history alone already points at day 3: no pin is needed.
      final chosen =
          (await workouts.loadChosenDay() as Success<ChosenDay?>).value;
      expect(chosen, isNull);
    },
  );

  test(
    'a workout in progress is untouched; the plan waits until it ends',
    () async {
      store.data['m1'] = const StoredGymPlan(
        plan: PlanTemplates.fiveDaySplit,
        version: 1,
        seenVersion: 1,
      );
      await workouts.saveDraft(
        WorkoutDraft(
          dayId: PlanTemplates.fiveDaySplit.days.first.id,
          startedAt: now,
        ),
      );
      server.plan = gymPlan(
        version: 2,
        updatedBy: 'captain',
        plan: renamedDay1(),
      );
      final o = outcome(await sync()('m1'));
      expect(o.deferred, isTrue);
      expect(o.replaced, isFalse);
      expect(o.toast, isTrue, reason: 'they are told right away');
      expect(store.data['m1']!.plan.days.first.name.en, isNot('Renamed'));
      expect(store.data['m1']!.pending?.version, 2);

      // The workout ends; the new plan applies, without a second toast.
      await workouts.saveDraft(null);
      final applied = outcome(await sync().applyPending('m1'));
      expect(applied.replaced, isTrue);
      expect(store.data['m1']!.plan.days.first.name.en, 'Renamed');
      expect(store.data['m1']!.pending, isNull);
      expect(outcome(await sync().applyPending('m1')).replaced, isFalse);
    },
  );

  test('offline keeps the local copy and says so', () async {
    store.data['m1'] = const StoredGymPlan(
      plan: PlanTemplates.fiveDaySplit,
      version: 3,
    );
    for (final f in [const NetworkFailure(), const TimeoutFailure()]) {
      server.failFetch = f;
      final o = outcome(await sync()('m1'));
      expect(o.offline, isTrue);
      expect(o.replaced, isFalse);
    }
    expect(store.data['m1']!.version, 3);
  });

  test('another failure is reported, and nothing changes', () async {
    store.data['m1'] = const StoredGymPlan(
      plan: PlanTemplates.fiveDaySplit,
      version: 3,
    );
    server.failFetch = const UnauthorizedFailure();
    final r = await sync()('m1');
    expect((r as Failed<PlanSyncOutcome>).failure, isA<UnauthorizedFailure>());
    expect(store.data['m1']!.version, 3);
  });

  test('a plan the captain took away clears the copy', () async {
    store.data['m1'] = const StoredGymPlan(
      plan: PlanTemplates.fiveDaySplit,
      version: 3,
    );
    server.plan = null;
    final o = outcome(await sync()('m1'));
    expect(o.replaced, isTrue);
    expect(store.data, isEmpty);
  });

  test('no plan at all is not an error', () async {
    server.plan = null;
    final o = outcome(await sync()('m1'));
    expect(o.replaced, isFalse);
  });
}
