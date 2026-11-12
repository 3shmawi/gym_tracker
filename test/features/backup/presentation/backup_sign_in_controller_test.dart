// Long fixtures and test names read better on one line here.
// ignore_for_file: lines_longer_than_80_chars

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/backup/data/in_memory_backup.dart';
import 'package:gym_tracker/features/backup/presentation/backup_sign_in_controller.dart';
import 'package:gym_tracker/features/backup/presentation/backup_sync.dart';
import 'package:gym_tracker/features/gym/domain/entities/account_session.dart';
import 'package:gym_tracker/features/gym/presentation/gym_providers.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../helpers/gym_fakes.dart';
import '../fakes.dart';

class _Signed extends AccountSessionNotifier {
  @override
  AccountSession build() =>
      const AccountSession(isSignedIn: true, email: 'me@example.com');
}

void main() {
  late FakeAccountRepository account;
  late FakeServer server;
  late InMemoryBackupSettings settings;
  late DateTime now;

  Future<ProviderContainer> app() async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer(
      overrides: [
        accountRepositoryProvider.overrideWithValue(account),
        accountSessionProvider.overrideWith(_Signed.new),
        backupRemoteProvider.overrideWithValue(server.phone()),
        backupQueueProvider.overrideWithValue(FakeQueue()),
        backupSettingsProvider.overrideWithValue(settings),
        localWorkoutRepositoryProvider.overrideWithValue(
          LocalWorkoutRepository(await SharedPreferences.getInstance()),
        ),
        clockProvider.overrideWithValue(() => now),
      ],
    );
    addTearDown(c.dispose);
    c.listen(backupSignInProvider, (_, _) {});
    return c;
  }

  setUp(() {
    account = FakeAccountRepository();
    server = FakeServer();
    settings = InMemoryBackupSettings();
    now = DateTime.utc(2026, 11, 12, 10);
  });

  test('a good email asks for a code and moves to the code step', () async {
    final c = await app();
    final controller = c.read(backupSignInProvider.notifier);
    await controller.submitEmail('  me@example.com ');
    final state = c.read(backupSignInProvider);
    expect(account.codesSentTo, ['me@example.com']);
    expect(state.step, BackupStep.code);
    expect(state.email, 'me@example.com');
    expect(state.problem, isNull);
  });

  test('something that is not an email never leaves the phone', () async {
    final c = await app();
    for (final bad in [
      '',
      'nope',
      'a@b',
      '<x>@y.com',
      'me@example.com\nBcc: a@b.c',
    ]) {
      await c.read(backupSignInProvider.notifier).submitEmail(bad);
      expect(
        c.read(backupSignInProvider).problem,
        BackupProblem.invalidEmail,
        reason: bad,
      );
    }
    expect(account.codesSentTo, isEmpty);
    expect(c.read(backupSignInProvider).step, BackupStep.email);
  });

  test(
    'no internet and too many tries say so, and stay on the email step',
    () async {
      final c = await app();
      account.sendCodeResult = const Failed(NetworkFailure());
      await c.read(backupSignInProvider.notifier).submitEmail('me@example.com');
      expect(c.read(backupSignInProvider).problem, BackupProblem.offline);
      account.sendCodeResult = Failed(
        AuthCodeFailure.of(
          const AuthApiException(
            'slow down',
            statusCode: '429',
            code: 'over_email_send_rate_limit',
          ),
        )!,
      );
      await c.read(backupSignInProvider.notifier).submitEmail('me@example.com');
      expect(c.read(backupSignInProvider).problem, BackupProblem.tooMany);
      expect(c.read(backupSignInProvider).step, BackupStep.email);
    },
  );

  test('the right code turns backup on and backs up what is waiting', () async {
    final c = await app();
    final controller = c.read(backupSignInProvider.notifier);
    await controller.submitEmail('me@example.com');
    await controller.submitCode('123 456');
    expect(account.codesTried, [('me@example.com', '123456')]);
    expect(settings.enabled, isTrue);
    expect(c.read(backupSignInProvider).step, BackupStep.done);
  });

  test('a wrong or expired code stays on the code step and does not turn backup on', () async {
    final c = await app();
    final controller = c.read(backupSignInProvider.notifier);
    await controller.submitEmail('me@example.com');
    account.verifyCodeResult = Failed(
      AuthCodeFailure.of(
        const AuthApiException(
          'expired',
          statusCode: '403',
          code: 'otp_expired',
        ),
      )!,
    );
    await controller.submitCode('000000');
    final state = c.read(backupSignInProvider);
    expect(state.step, BackupStep.code);
    expect(state.problem, BackupProblem.wrongOrExpired);
    expect(settings.enabled, isFalse);
  });

  test('a code that is not six digits is refused before it is sent', () async {
    final c = await app();
    final controller = c.read(backupSignInProvider.notifier);
    await controller.submitEmail('me@example.com');
    for (final bad in ['', '12345', 'abcdef', "'; drop"]) {
      await controller.submitCode(bad);
      expect(
        c.read(backupSignInProvider).problem,
        BackupProblem.invalidCode,
        reason: bad,
      );
    }
    expect(account.codesTried, isEmpty);
  });

  test('a new code can be asked for only after 60 seconds', () async {
    final c = await app();
    final controller = c.read(backupSignInProvider.notifier);
    await controller.submitEmail('me@example.com');
    expect(controller.resendIn(), 60);
    await controller.resend();
    expect(account.codesSentTo, hasLength(1), reason: 'too early');
    now = now.add(const Duration(seconds: 30));
    expect(controller.resendIn(), 30);
    now = now.add(const Duration(seconds: 31));
    expect(controller.resendIn(), 0);
    await controller.resend();
    expect(account.codesSentTo, hasLength(2));
    expect(controller.resendIn(), 60, reason: 'the clock starts again');
  });

  test('another email goes back to the first step', () async {
    final c = await app();
    final controller = c.read(backupSignInProvider.notifier);
    await controller.submitEmail('me@example.com');
    controller.changeEmail();
    expect(c.read(backupSignInProvider).step, BackupStep.email);
    expect(controller.resendIn(), 0);
  });

  test('an email that belongs to another account offers to sign in to it', () async {
    final c = await app();
    final controller = c.read(backupSignInProvider.notifier);
    account.sendCodeResult = Failed(
      AuthCodeFailure.of(
        const AuthApiException(
          'exists',
          statusCode: '422',
          code: 'email_exists',
        ),
      )!,
    );
    await controller.submitEmail('me@example.com');
    expect(c.read(backupSignInProvider).problem, BackupProblem.emailTaken);
    // Using it: this phone leaves the gym trainee account, then a code is sent.
    account.sendCodeResult = const Success(null);
    await controller.useExistingAccount();
    expect(account.signOuts, 1);
    expect(account.codesSentTo, hasLength(2));
    expect(c.read(backupSignInProvider).step, BackupStep.code);
  });

  test(
    '"use the existing account" does nothing unless that was the problem',
    () async {
      final c = await app();
      await c.read(backupSignInProvider.notifier).useExistingAccount();
      expect(account.signOuts, 0);
    },
  );

  test('two taps at once send one request', () async {
    final c = await app();
    final controller = c.read(backupSignInProvider.notifier);
    await Future.wait([
      controller.submitEmail('me@example.com'),
      controller.submitEmail('me@example.com'),
    ]);
    expect(account.codesSentTo, hasLength(1));
  });
}
