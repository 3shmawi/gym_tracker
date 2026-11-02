import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/invite_code.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'init can run more than once (the app restarts in one process)',
    () async {
      SharedPreferences.setMockInitialValues({});
      await Dependencies.init();
      final first = Dependencies.workoutRepository;
      await Dependencies.init();
      expect(Dependencies.workoutRepository, isNot(same(first)));
    },
  );

  test(
    'without Supabase values, joining is "offline" and nobody is signed in',
    () async {
      SharedPreferences.setMockInitialValues({});
      await Dependencies.init();
      expect(Dependencies.accountRepository.session.isSignedIn, isFalse);
      final result = await Dependencies.gymRepository.redeem(
        InviteCode.tryParse('K7M2QX')!,
      );
      expect((result as Failed<JoinedGym>).failure, isA<NetworkFailure>());
      final memberships = await Dependencies.gymRepository.loadMemberships();
      expect((memberships as Success<List<Membership>>).value, isEmpty);
    },
  );

  test('the gym state is saved on the phone', () async {
    SharedPreferences.setMockInitialValues({});
    await Dependencies.init();
    await Dependencies.gymLocalRepository.saveOnboardingDone();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('gym.onboarding_done'), isTrue);
  });
}
