import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/feature_flags/feature_flags.dart';
import 'package:gym_tracker/features/backup/data/in_memory_backup.dart';
import 'package:gym_tracker/features/backup/presentation/backup_sync.dart';
import 'package:gym_tracker/features/gym/data/repositories/prefs_gym_history_cursor.dart';
import 'package:gym_tracker/features/gym/domain/entities/account_session.dart';
import 'package:gym_tracker/features/gym/presentation/gym_providers.dart';
import 'package:gym_tracker/features/gym/presentation/gym_sync.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/repositories/restore_sink.dart';
import 'package:gym_tracker/l10n/gen/app_localizations.dart';

import '../../../helpers/gym_fakes.dart';
import '../../backup/fakes.dart';

class _Signed extends AccountSessionNotifier {
  @override
  AccountSession build() => anonymousSession;
}

class _Out extends AccountSessionNotifier {
  @override
  AccountSession build() => AccountSession.signedOut;
}

WorkoutSession workout(int i) => WorkoutSession(
  dayId: 'day-${i % 5}',
  finishedAt: DateTime.utc(2026).add(Duration(hours: i * 5)),
  sets: [LoggedSet(exerciseId: 'ex_$i', weight: 20.0 + i, reps: 8)],
);

void main() {
  late FakeServer server;
  late FakeSink sink;
  late InMemoryGymHistoryCursor cursor;
  late InMemoryBackupSettings backup;

  setUp(() {
    server = FakeServer();
    for (final i in [1, 2, 3]) {
      server.sessions[workout(i).clientId] = workout(i);
    }
    sink = FakeSink(FakeQueue());
    cursor = InMemoryGymHistoryCursor();
    backup = InMemoryBackupSettings();
    FeatureFlags.overrides[Flags.gymHistoryRestore] = true;
  });
  tearDown(FeatureFlags.overrides.clear);

  ProviderContainer app({bool signedIn = true, RestoreSink? into}) {
    final c = ProviderContainer(
      overrides: [
        accountSessionProvider.overrideWith(signedIn ? _Signed.new : _Out.new),
        backupRemoteProvider.overrideWithValue(server.phone()),
        restoreSinkProvider.overrideWithValue(into ?? sink),
        backupSettingsProvider.overrideWithValue(backup),
        gymHistoryCursorProvider.overrideWithValue(cursor),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test(
    'after a recovery the workouts come back, and the toast counts them',
    () async {
      final c = app();
      await c.read(gymSyncProvider).restoreHistory();
      expect(sink.local, hasLength(3));
      expect(c.read(historyRestoredToastProvider), (count: 3, seq: 1));
      // Done: the next trigger the same day does nothing, and no new toast.
      final calls = server.fetchCalls;
      await c.read(gymSyncProvider).restoreHistory();
      expect(server.fetchCalls, calls);
      expect(c.read(historyRestoredToastProvider).seq, 1);
    },
  );

  test('nothing came back: no toast', () async {
    server.sessions.clear();
    final c = app();
    await c.read(gymSyncProvider).restoreHistory();
    expect(c.read(historyRestoredToastProvider).seq, 0);
  });

  test('calls that come together share one run', () async {
    final c = app();
    final sync = c.read(gymSyncProvider);
    await Future.wait([sync.restoreHistory(), sync.restoreHistory()]);
    expect(sink.local, hasLength(3));
    expect(server.fetchCalls, 1);
  });

  group('it does not run', () {
    Future<void> expectNothing(ProviderContainer c) async {
      await c.read(gymSyncProvider).restoreHistory();
      expect(server.fetchCalls, 0);
      expect(sink.local, isEmpty);
    }

    test('with the flag off', () async {
      FeatureFlags.overrides[Flags.gymHistoryRestore] = false;
      await expectNothing(app());
    });

    test('signed out', () => expectNothing(app(signedIn: false)));

    test('with backup on (the backup restore brings them)', () async {
      backup = InMemoryBackupSettings(enabled: true);
      await expectNothing(app());
    });

    test('without a phone database', () async {
      await expectNothing(app(into: const EmptyRestoreSink()));
    });
  });

  test('analytics get a range, never the count', () {
    expect(GymSync.restoredBucket(1), '1_10');
    expect(GymSync.restoredBucket(10), '1_10');
    expect(GymSync.restoredBucket(11), '11_50');
    expect(GymSync.restoredBucket(200), '51_200');
    expect(GymSync.restoredBucket(201), '200_plus');
  });

  test('the toast reads right in both languages', () {
    final en = lookupAppLocalizations(const Locale('en'));
    final ar = lookupAppLocalizations(const Locale('ar'));
    expect(en.gymHistoryRestored(1), 'Your workout is back');
    expect(en.gymHistoryRestored(3), 'Your 3 workouts are back');
    expect(ar.gymHistoryRestored(1), 'رجع تمرينك');
    expect(ar.gymHistoryRestored(2), 'رجعوا تمرينينك');
    expect(ar.gymHistoryRestored(3), 'رجعوا 3 تمارين ليك');
    expect(ar.gymHistoryRestored(25), 'رجع 25 تمرين ليك');
  });
}
