import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/features/backup/data/in_memory_backup.dart';
import 'package:gym_tracker/features/backup/domain/entities/backup_status.dart';
import 'package:gym_tracker/features/backup/presentation/backup_sync.dart';
import 'package:gym_tracker/features/gym/domain/entities/account_session.dart';
import 'package:gym_tracker/features/gym/presentation/gym_providers.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes.dart';

class _SignedIn extends AccountSessionNotifier {
  @override
  AccountSession build() =>
      const AccountSession(isSignedIn: true, email: 'a@b.c');
}

class _SignedOut extends AccountSessionNotifier {
  @override
  AccountSession build() => AccountSession.signedOut;
}

WorkoutSession workout(int i) => WorkoutSession(
  dayId: legacyDayId(i % 5),
  finishedAt: DateTime.utc(2026).add(Duration(hours: i)),
  sets: const [],
);

void main() {
  late FakeServer server;
  late FakeQueue queue;
  late InMemoryBackupSettings settings;

  Future<ProviderContainer> app({bool signedIn = true}) async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer(
      overrides: [
        backupRemoteProvider.overrideWithValue(server.phone()),
        backupQueueProvider.overrideWithValue(queue),
        backupSettingsProvider.overrideWithValue(settings),
        accountSessionProvider.overrideWith(
          signedIn ? _SignedIn.new : _SignedOut.new,
        ),
        localWorkoutRepositoryProvider.overrideWithValue(
          LocalWorkoutRepository(await SharedPreferences.getInstance()),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    server = FakeServer();
    queue = FakeQueue();
    settings = InMemoryBackupSettings();
  });

  test('off by default: running does nothing and says off', () async {
    final c = await app();
    queue.all.add(workout(1));
    await c.read(backupSyncProvider).run();
    expect(c.read(backupStatusProvider), BackupStatus.off);
    expect(server.uploadCalls, 0);
  });

  test('turning it on backs up what is waiting and shows it', () async {
    final c = await app();
    queue.all.addAll([workout(1), workout(2)]);
    await c.read(backupSyncProvider).enable();
    expect(settings.enabled, isTrue);
    expect(server.sessions, hasLength(2));
    expect(c.read(backupStatusProvider).state, BackupState.upToDate);
  });

  test('no network: it waits and says how many', () async {
    server.failWith = const NetworkFailure();
    final c = await app();
    queue.all.addAll([workout(1), workout(2), workout(3)]);
    await c.read(backupSyncProvider).enable();
    final status = c.read(backupStatusProvider);
    expect(status.state, BackupState.waiting);
    expect(status.pending, 3);
    // Back online: the next run finishes it.
    server.failWith = null;
    await c.read(backupSyncProvider).run();
    expect(c.read(backupStatusProvider).state, BackupState.upToDate);
  });

  test(
    'signed out while backup is on: asks to sign in again, sends nothing',
    () async {
      settings.enabled = true;
      final c = await app(signedIn: false);
      queue.all.add(workout(1));
      await c.read(backupSyncProvider).run();
      expect(c.read(backupStatusProvider).state, BackupState.signInAgain);
      expect(server.uploadCalls, 0);
    },
  );

  test(
    "turning it off stops further runs and keeps the phone's training",
    () async {
      final c = await app();
      queue.all.add(workout(1));
      await c.read(backupSyncProvider).enable();
      await c.read(backupSyncProvider).disable();
      expect(settings.enabled, isFalse);
      expect(c.read(backupStatusProvider), BackupStatus.off);
      queue.all.add(workout(2));
      await c.read(backupSyncProvider).run();
      expect(server.sessions, hasLength(1));
      expect(queue.all, hasLength(2));
    },
  );

  test('two runs at once do not upload twice', () async {
    final c = await app();
    settings.enabled = true;
    queue.all.addAll([for (var i = 1; i <= 3; i++) workout(i)]);
    final sync = c.read(backupSyncProvider);
    await Future.wait([sync.run(), sync.run()]);
    expect(server.uploadCalls, 1);
  });

  test('the back-off grows from 30 seconds to 15 minutes', () {
    expect(BackupSync.backoff(1), const Duration(seconds: 30));
    expect(BackupSync.backoff(2), const Duration(minutes: 1));
    expect(BackupSync.backoff(3), const Duration(minutes: 2));
    expect(BackupSync.backoff(20), const Duration(minutes: 15));
  });
}
