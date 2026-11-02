import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/data/repositories/in_memory_gym_local_repository.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_role.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/entities/workspace.dart';
import 'package:gym_tracker/features/gym/domain/usecases/end_account.dart';
import 'package:gym_tracker/features/gym/domain/usecases/redeem_invite.dart';
import 'package:gym_tracker/features/gym/domain/usecases/refresh_memberships.dart';
import 'package:gym_tracker/features/gym/domain/usecases/switch_workspace.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/gym_fakes.dart';

void main() {
  group('RedeemInvite', () {
    test(
      'success makes the gym the active workspace and keeps a copy',
      () async {
        final gyms = FakeGymRepository(
          redeemResult: Success(joinedGym(id: 'm7')),
        );
        final local = InMemoryGymLocalRepository(
          memberships: [member(id: 'old', gym: 'Peak')],
        );
        final result = await RedeemInvite(gyms, local)(testCode);

        expect(result, isA<Success<JoinedGym>>());
        expect(gyms.redeemed, [testCode]);
        expect(local.workspace, const GymWorkspace('m7'));
        expect(local.onboardingDone, isTrue);
        expect(local.memberships.map((m) => m.id), ['old', 'm7']);
      },
    );

    test('joining the same gym again does not duplicate it', () async {
      final gyms = FakeGymRepository(redeemResult: Success(joinedGym()));
      final local = InMemoryGymLocalRepository(memberships: [member()]);
      await RedeemInvite(gyms, local)(testCode);
      expect(local.memberships.map((m) => m.id), ['m1']);
    });

    test('a refused code changes nothing on the phone', () async {
      final gyms = FakeGymRepository(
        redeemResult: const Failed(InviteFailure(InviteProblem.used)),
      );
      final local = InMemoryGymLocalRepository(
        workspace: const GymWorkspace('keep'),
        memberships: [member(id: 'keep')],
      );
      final result = await RedeemInvite(gyms, local)(testCode);

      expect(
        (result as Failed<JoinedGym>).failure,
        isA<InviteFailure>().having(
          (f) => f.problem,
          'problem',
          InviteProblem.used,
        ),
      );
      expect(local.workspace, const GymWorkspace('keep'));
      expect(local.onboardingDone, isFalse);
      expect(local.memberships.map((m) => m.id), ['keep']);
    });

    test('an offline failure passes through untouched', () async {
      final gyms = FakeGymRepository(redeemResult: offline);
      final result = await RedeemInvite(gyms, InMemoryGymLocalRepository())(
        testCode,
      );
      expect((result as Failed<JoinedGym>).failure, isA<NetworkFailure>());
    });
  });

  group('RefreshMemberships', () {
    test('keeps the active gym while its membership is active', () async {
      final gyms = FakeGymRepository(memberships: Success([member()]));
      final local = InMemoryGymLocalRepository(
        workspace: const GymWorkspace('m1'),
      );
      final result = await RefreshMemberships(gyms, local)();
      final snapshot = (result as Success<GymSnapshot>).value;
      expect(snapshot.workspace, const GymWorkspace('m1'));
      expect(snapshot.activeMembership?.gym.name, 'Iron House');
      expect(local.memberships, hasLength(1));
    });

    test('falls back to solo when the membership ended (revoked)', () async {
      final gyms = FakeGymRepository(
        memberships: Success([member(status: MembershipStatus.ended)]),
      );
      final local = InMemoryGymLocalRepository(
        workspace: const GymWorkspace('m1'),
      );
      final snapshot =
          ((await RefreshMemberships(gyms, local)()) as Success<GymSnapshot>)
              .value;
      expect(snapshot.workspace, const SoloWorkspace());
      expect(local.workspace, const SoloWorkspace());
      expect(snapshot.memberships.single.status, MembershipStatus.ended);
    });

    test('falls back to solo when the gym is gone from the server', () async {
      final gyms = FakeGymRepository(memberships: const Success([]));
      final local = InMemoryGymLocalRepository(
        workspace: const GymWorkspace('m1'),
        memberships: [member()],
      );
      final snapshot =
          ((await RefreshMemberships(gyms, local)()) as Success<GymSnapshot>)
              .value;
      expect(snapshot.workspace, const SoloWorkspace());
      expect(local.memberships, isEmpty);
    });

    test('offline keeps everything the phone has', () async {
      final gyms = FakeGymRepository(memberships: offline);
      final local = InMemoryGymLocalRepository(
        workspace: const GymWorkspace('m1'),
        memberships: [member()],
      );
      final result = await RefreshMemberships(gyms, local)();
      expect(result, isA<Failed<GymSnapshot>>());
      expect(local.workspace, const GymWorkspace('m1'));
      expect(local.memberships, hasLength(1));
    });

    test(
      'LoadGymSnapshot reads the cache and never opens an ended gym',
      () async {
        final local = InMemoryGymLocalRepository(
          workspace: const GymWorkspace('m1'),
          memberships: [member(status: MembershipStatus.ended)],
        );
        final snapshot = await LoadGymSnapshot(local)();
        expect(snapshot.workspace, const SoloWorkspace());
        expect(snapshot.memberships, hasLength(1));
      },
    );
  });

  group('SwitchWorkspace', () {
    final current = GymSnapshot(
      memberships: [
        member(),
        member(id: 'gone', status: MembershipStatus.ended),
        member(id: 'p', gym: 'Peak', role: GymRole.captain),
      ],
    );

    test('picks an active gym and solo', () async {
      final local = InMemoryGymLocalRepository();
      final toGym = await SwitchWorkspace(local)(
        const GymWorkspace('p'),
        current,
      );
      expect(
        (toGym as Success<GymSnapshot>).value.workspace,
        const GymWorkspace('p'),
      );
      expect(local.workspace, const GymWorkspace('p'));
      final toSolo = await SwitchWorkspace(local)(
        const SoloWorkspace(),
        current,
      );
      expect(toSolo, isA<Success<GymSnapshot>>());
      expect(local.workspace, const SoloWorkspace());
    });

    test('refuses an ended or unknown membership', () async {
      final local = InMemoryGymLocalRepository();
      for (final id in ['gone', 'nope', '']) {
        final result = await SwitchWorkspace(local)(GymWorkspace(id), current);
        expect(result, isA<Failed<GymSnapshot>>(), reason: id);
      }
      expect(local.workspace, const SoloWorkspace());
    });
  });

  group('SignOut / DeleteAccount', () {
    late FakeAccountRepository account;
    late InMemoryGymLocalRepository local;
    late LocalWorkoutRepository workouts;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        LocalWorkoutRepository.historyKey: '[]',
        LocalWorkoutRepository.levelKey: 'pro',
        LocalWorkoutRepository.planKey: '{"keep":"me"}',
      });
      workouts = LocalWorkoutRepository(await SharedPreferences.getInstance());
      account = FakeAccountRepository(anonymousSession);
      local = InMemoryGymLocalRepository(
        workspace: const GymWorkspace('m1'),
        memberships: [member()],
      );
    });

    test('sign out ends the session and goes back to solo', () async {
      final result = await SignOut(account, local)();
      expect(result, isA<Success<void>>());
      expect(account.signOuts, 1);
      expect(local.workspace, const SoloWorkspace());
      expect(local.memberships, isEmpty);
    });

    test('a failed sign out keeps the gym state', () async {
      account.signOutResult = offline;
      final result = await SignOut(account, local)();
      expect(result, isA<Failed<void>>());
      expect(local.workspace, const GymWorkspace('m1'));
    });

    test(
      'delete: server first, then the gym state; workouts stay by default',
      () async {
        final result = await DeleteAccount(account, local, workouts)(
          eraseLocalWorkouts: false,
        );
        expect(result, isA<Success<void>>());
        expect(local.workspace, const SoloWorkspace());
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(LocalWorkoutRepository.levelKey), 'pro');
      },
    );

    test(
      'delete with "also erase workouts" clears history, keeps the plan',
      () async {
        await DeleteAccount(account, local, workouts)(eraseLocalWorkouts: true);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(LocalWorkoutRepository.historyKey), isNull);
        expect(prefs.getString(LocalWorkoutRepository.levelKey), isNull);
        expect(prefs.getString(LocalWorkoutRepository.planKey), isNotNull);
      },
    );

    test('a refused delete (last owner) changes nothing', () async {
      account.deleteResult = const Failed(LastOwnerFailure(['Iron House']));
      final result = await DeleteAccount(account, local, workouts)(
        eraseLocalWorkouts: true,
      );
      expect(
        (result as Failed<void>).failure,
        isA<LastOwnerFailure>().having((f) => f.gymNames, 'gyms', [
          'Iron House',
        ]),
      );
      expect(local.workspace, const GymWorkspace('m1'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(LocalWorkoutRepository.historyKey), isNotNull);
    });

    test('HandleSessionEnded forgets the gym state', () async {
      await HandleSessionEnded(local)();
      expect(local.workspace, const SoloWorkspace());
      expect(local.memberships, isEmpty);
    });
  });

  test(
    'LocalWorkoutRepository.clearHistory removes only workout state',
    () async {
      SharedPreferences.setMockInitialValues({
        LocalWorkoutRepository.historyKey: '[]',
        LocalWorkoutRepository.draftKey: '{}',
        LocalWorkoutRepository.chosenDayKey: '{}',
        LocalWorkoutRepository.levelKey: 'pro',
        LocalWorkoutRepository.planKey: '{}',
        'settings.locale': 'ar',
      });
      final prefs = await SharedPreferences.getInstance();
      final result = await LocalWorkoutRepository(prefs).clearHistory();
      expect(result, isA<Success<void>>());
      expect(prefs.getKeys(), {
        LocalWorkoutRepository.planKey,
        'settings.locale',
      });
    },
  );

  test('Gym keeps its history setting', () {
    expect(
      const Gym(id: 'g', name: 'x', historyAfterEnd: HistoryAfterEnd.locked),
      isNot(const Gym(id: 'g', name: 'x')),
    );
  });
}
