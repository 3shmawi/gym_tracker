import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/account_session.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_plan.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_role.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/repositories/session_outbox.dart';
import 'package:gym_tracker/features/gym/presentation/gym_providers.dart';
import 'package:gym_tracker/features/gym/presentation/gym_sync.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_draft.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/usecases/edit_plan.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/plan_editor_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/gym_fakes.dart';
import '../../../helpers/plan_sync_fakes.dart';

/// The membership the test app is signed in with; changing it is the
/// captain changing the member's rights (or removing them).
final _membership = NotifierProvider<_Membership, Membership?>(_Membership.new);

class _Membership extends Notifier<Membership?> {
  @override
  Membership? build() => null;
  // A method (not a setter) so tests read like "the captain sets".
  // ignore: use_setters_to_change_properties
  void set(Membership? m) => state = m;
}

class _Signed extends AccountSessionNotifier {
  @override
  AccountSession build() => anonymousSession;
}

const _everything = GymPermissions(editTargets: true, editPlan: true);

void main() {
  late LocalWorkoutRepository local;
  late FakePlanServer server;
  late MemoryPlanStore store;
  late MemoryOutbox outbox;
  late FakeUploader uploader;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    local = LocalWorkoutRepository(await SharedPreferences.getInstance());
    server = FakePlanServer();
    store = MemoryPlanStore();
    outbox = MemoryOutbox();
    uploader = FakeUploader();
  });

  ProviderContainer app(Membership? m) {
    final c = ProviderContainer(
      overrides: [
        ...gymProviderOverrides,
        localWorkoutRepositoryProvider.overrideWithValue(local),
        gymPlanRepositoryProvider.overrideWithValue(server),
        gymPlanStoreProvider.overrideWithValue(store),
        sessionOutboxProvider.overrideWithValue(outbox),
        sessionUploaderProvider.overrideWithValue(uploader),
        accountSessionProvider.overrideWith(_Signed.new),
        activeMembershipProvider.overrideWith((ref) => ref.watch(_membership)),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 11, 5, 18)),
      ],
    );
    addTearDown(c.dispose);
    c.read(_membership.notifier).set(m);
    c.listen(planEditorControllerProvider, (_, _) {});
    return c;
  }

  Future<PlanEditorController> editor(ProviderContainer c) => c
      .read(planEditorControllerProvider.future)
      .then((_) => c.read(planEditorControllerProvider.notifier));

  WorkoutSession finished() => WorkoutSession(
    dayId: 'day-1',
    finishedAt: DateTime.utc(2026, 11, 5, 17),
    sets: const [LoggedSet(exerciseId: 'bench', weight: 60, reps: 8)],
  );

  group('the plan comes from the gym', () {
    test(
      'first time in a gym: loaded from the server, kept on the phone',
      () async {
        server.plan = gymPlan(version: 3, updatedBy: 'captain-m');
        final c = app(member());
        final plan = await c.read(nextWorkoutControllerProvider.future);
        expect(plan!.day.id, PlanTemplates.fiveDaySplit.days.first.id);
        expect(store.data['m1']!.version, 3);
      },
    );

    test('offline with a copy: the copy is the plan', () async {
      await store.save(
        'm1',
        StoredGymPlan(plan: renamedDay1(), version: 2, seenVersion: 2),
      );
      server.failFetch = const NetworkFailure();
      final c = app(member());
      await c.read(gymSyncProvider).syncPlan();
      final next = await c.read(nextWorkoutControllerProvider.future);
      expect(next!.day.name.en, 'Renamed');
    });

    test('offline and no copy: no plan, no crash', () async {
      server.failFetch = const NetworkFailure();
      final c = app(member());
      expect(await c.read(nextWorkoutControllerProvider.future), isNull);
    });

    test('the solo plan is not touched while in a gym', () async {
      await local.savePlan(PlanTemplates.fiveDaySplit);
      server.plan = gymPlan(plan: renamedDay1());
      final c = app(member());
      final next = await c.read(nextWorkoutControllerProvider.future);
      expect(next!.day.name.en, 'Renamed');
      final solo = (await local.loadPlan() as Success<WorkoutPlan?>).value;
      expect(solo!.days.first.name.en, isNot('Renamed'));
    });
  });

  group('the captain wins', () {
    test('a new version replaces the plan and says so once', () async {
      server.plan = gymPlan(updatedBy: 'm1');
      final c = app(member());
      await c.read(gymSyncProvider).syncPlan();
      expect(c.read(planUpdatedToastProvider), 0);

      server.plan = gymPlan(
        version: 2,
        updatedBy: 'captain-m',
        plan: renamedDay1(),
      );
      await c.read(gymSyncProvider).syncPlan();
      expect(c.read(planUpdatedToastProvider), 1);
      expect(store.data['m1']!.plan.days.first.name.en, 'Renamed');

      await c.read(gymSyncProvider).syncPlan();
      expect(c.read(planUpdatedToastProvider), 1, reason: 'same version');
    });

    test('a workout in progress keeps the old plan until it ends', () async {
      server.plan = gymPlan(updatedBy: 'm1');
      final c = app(member());
      await c.read(gymSyncProvider).syncPlan();
      await local.saveDraft(
        WorkoutDraft(dayId: 'day-1', startedAt: DateTime.utc(2026, 11, 5, 16)),
      );
      server.plan = gymPlan(
        version: 2,
        updatedBy: 'captain-m',
        plan: renamedDay1(),
      );
      await c.read(gymSyncProvider).syncPlan();
      expect(store.data['m1']!.plan.days.first.name.en, isNot('Renamed'));
      expect(store.data['m1']!.pending!.version, 2);

      await local.saveDraft(null);
      await c.read(gymSyncProvider).afterWorkout();
      expect(store.data['m1']!.plan.days.first.name.en, 'Renamed');
      expect(c.read(planUpdatedToastProvider), 1);
    });

    test(
      "saving over the captain's newer plan is refused and reloads",
      () async {
        server.plan = gymPlan(updatedBy: 'm1');
        final c = app(member(permissions: _everything));
        final e = await editor(c);
        // The captain changes the plan after the editor loaded it.
        server.plan = gymPlan(
          version: 2,
          updatedBy: 'captain-m',
          plan: renamedDay1(),
        );
        final error = await e.renameDay(
          'day-1',
          const LocalizedName(ar: 'س', en: 'Mine'),
        );
        expect(error, isNull);
        final state = c.read(planEditorControllerProvider).requireValue;
        expect(state.saveFailure, isA<PlanChangedFailure>());
        // Their plan is on the phone, mine is gone.
        expect(store.data['m1']!.plan.days.first.name.en, 'Renamed');
        await e.retrySave();
        await c.read(planEditorControllerProvider.future);
        final after = c.read(planEditorControllerProvider).requireValue;
        expect(after.saveFailure, isNull);
        expect(after.plan.days.first.name.en, 'Renamed');
      },
    );
  });

  group('rights', () {
    test('a trainee with targets only changes targets', () async {
      server.plan = gymPlan(updatedBy: 'm1');
      final c = app(member());
      final e = await editor(c);
      final day = PlanTemplates.fiveDaySplit.days.first;
      final ex = day.exercises.first;
      expect(
        await e.setTargets(day.id, ex.id, sets: ex.targetSets + 1),
        isNull,
      );
      expect(server.saves, 1);
      expect(
        await e.renameDay(day.id, const LocalizedName(ar: 'س', en: 'X')),
        PlanEditError.notAllowed,
      );
      expect(await e.deleteExercise(day.id, ex.id), PlanEditError.notAllowed);
      expect(await e.addDay(const LocalizedName(ar: 'س', en: 'X')), isNull);
      expect(server.saves, 1, reason: 'refused edits never reach the server');
    });

    test('a right revoked while the editor is open locks it', () async {
      server.plan = gymPlan(updatedBy: 'm1');
      final c = app(member(permissions: _everything));
      final e = await editor(c);
      expect(
        c
            .read(planEditorControllerProvider)
            .requireValue
            .permissions
            .editStructure,
        isTrue,
      );

      // The captain switches the rights off.
      c
          .read(_membership.notifier)
          .set(member(permissions: const GymPermissions()));
      await c.read(planEditorControllerProvider.future);
      final locked = c.read(planEditorControllerProvider).requireValue;
      expect(locked.permissions.readOnly, isTrue);

      final day = PlanTemplates.fiveDaySplit.days.first;
      final fresh = c.read(planEditorControllerProvider.notifier);
      expect(
        await fresh.renameDay(day.id, const LocalizedName(ar: 'س', en: 'X')),
        PlanEditError.notAllowed,
      );
      expect(
        await fresh.setTargets(day.id, day.exercises.first.id, sets: 5),
        PlanEditError.notAllowed,
      );
      expect(server.saves, 0);
      expect(e, isNotNull);
    });

    test('the server refusing (revoked there first) is an error', () async {
      server.plan = gymPlan(updatedBy: 'm1');
      final c = app(member(permissions: _everything));
      final e = await editor(c);
      server.failSave = const UnauthorizedFailure();
      final day = PlanTemplates.fiveDaySplit.days.first;
      await e.renameDay(day.id, const LocalizedName(ar: 'س', en: 'X'));
      final state = c.read(planEditorControllerProvider).requireValue;
      expect(state.saveFailure, isA<UnauthorizedFailure>());
      expect(store.data['m1']!.version, 1, reason: 'nothing saved');
    });
  });

  group('finished workouts are uploaded', () {
    test('a finished workout is saved, queued, then uploaded once', () async {
      server.plan = gymPlan(updatedBy: 'm1');
      final c = app(member());
      await c.read(nextWorkoutControllerProvider.future);
      await c.read(workoutRepositoryProvider).saveSession(finished());
      expect(outbox.entries, hasLength(1));
      expect(outbox.entries.single.session.membershipId, 'm1');
      expect(outbox.entries.single.gymId, 'g-m1');
      expect((await local.loadHistory() as Success).value, hasLength(1));

      await c.read(gymSyncProvider).uploadPending();
      expect(uploader.stored, hasLength(1));
      expect(outbox.entries, isEmpty);
      await c.read(gymSyncProvider).uploadPending();
      expect(uploader.calls, 1, reason: 'nothing left to send');
    });

    test('offline: stays queued and goes up later, not twice', () async {
      final c = app(member());
      await c.read(workoutRepositoryProvider).saveSession(finished());
      uploader.script.add('fail');
      await c.read(gymSyncProvider).uploadPending();
      expect(outbox.entries, hasLength(1));
      await c.read(gymSyncProvider).uploadPending();
      expect(outbox.entries, isEmpty);
      expect(uploader.stored, hasLength(1));
    });

    test('signed out: nothing is sent', () async {
      final c = ProviderContainer(
        overrides: [
          ...gymProviderOverrides,
          localWorkoutRepositoryProvider.overrideWithValue(local),
          sessionOutboxProvider.overrideWithValue(outbox),
          sessionUploaderProvider.overrideWithValue(uploader),
          accountSessionProvider.overrideWith(AccountSessionNotifier.new),
        ],
      );
      addTearDown(c.dispose);
      await outbox.add(
        OutboxEntry(
          clientId: 'a' * 64,
          gymId: 'g-m1',
          membershipId: 'm1',
          session: finished(),
        ),
      );
      await c.read(gymSyncProvider).uploadPending();
      expect(uploader.calls, 0);
    });

    test('solo workouts are never queued', () async {
      final c = app(null);
      await c.read(workoutRepositoryProvider).saveSession(finished());
      expect(outbox.entries, isEmpty);
    });

    test('the back-off grows and is capped', () {
      expect(GymSync.backoff(1), const Duration(seconds: 30));
      expect(GymSync.backoff(2), const Duration(seconds: 60));
      expect(GymSync.backoff(3), const Duration(seconds: 120));
      expect(GymSync.backoff(30), const Duration(minutes: 15));
    });
  });
}
