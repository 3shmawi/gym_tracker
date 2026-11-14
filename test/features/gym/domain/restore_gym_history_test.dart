import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/backup/domain/entities/restore.dart';
import 'package:gym_tracker/features/backup/domain/usecases/restore_sessions.dart';
import 'package:gym_tracker/features/gym/data/repositories/prefs_gym_history_cursor.dart';
import 'package:gym_tracker/features/gym/data/repositories/prefs_gym_local_repository.dart';
import 'package:gym_tracker/features/gym/domain/usecases/restore_gym_history.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/repositories/restore_sink.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../backup/fakes.dart';

WorkoutSession workout(int i) => WorkoutSession(
  dayId: 'day-${i % 5}',
  finishedAt: DateTime.utc(2026).add(Duration(hours: i * 5)),
  sets: [LoggedSet(exerciseId: 'ex_$i', weight: 20.0 + i, reps: 8)],
);

/// A phone database that refuses pages (like one at its 100 000-row cap).
class _FullSink implements RestoreSink {
  @override
  Future<int> addBackedUp(List<WorkoutSession> sessions) async =>
      throw StateError('the phone holds at most 100000 workouts');

  @override
  Future<int> count() async => 100000;
}

void main() {
  late FakeServer server;
  late FakeSink sink;
  late DateTime now;
  late InMemoryGymHistoryCursor store;

  RestoreGymHistory restore({RestoreSink? into}) => RestoreGymHistory(
    remote: server.phone(),
    sink: into ?? sink,
    store: store,
    now: () => now,
  );

  void serve(Iterable<int> ids) {
    for (final i in ids) {
      server.sessions[workout(i).clientId] = workout(i);
    }
  }

  setUp(() {
    server = FakeServer();
    sink = FakeSink(FakeQueue());
    now = DateTime.utc(2026, 11, 14, 18);
    store = InMemoryGymHistoryCursor(now: () => now);
  });

  group(RestoreSessions, () {
    test('pages down everything, oldest first, then says done', () async {
      serve(List.generate(7, (i) => i + 1));
      final result = await RestoreSessions(
        remote: server.phone(),
        sink: sink,
        cursor: store,
        pageSize: 3,
      )();
      expect((result as Success<RestoredSessions>).value.added, 7);
      expect(store.read(), RestoreCursor.done);
      expect(server.fetchCalls, 3);
    });

    test('a refused page is a failure, the position stays', () async {
      serve([1, 2]);
      final result = await RestoreSessions(
        remote: server.phone(),
        sink: _FullSink(),
        cursor: store,
      )();
      expect(result, isA<Failed<RestoredSessions>>());
      expect(store.read(), isNull, reason: 'nothing was taken');
    });
  });

  group(RestoreGymHistory, () {
    test('a recovery: every workout comes back, counted once', () async {
      serve([1, 2, 3]);
      final run = (await restore()())! as Success<GymHistoryRun>;
      expect(run.value, (finished: true, added: 3, skipped: false));
      expect(sink.local, hasLength(3));
      expect(store.added, 0, reason: 'the total is reset once shown');
    });

    test('a new person: one empty page, done, nothing to show', () async {
      final run = (await restore()())! as Success<GymHistoryRun>;
      expect(run.value.added, 0);
      expect(server.fetchCalls, 1);
      expect(await restore()(), isNull, reason: 'done, checked lately');
    });

    test('cut short: the next run carries on and counts the whole', () async {
      serve(List.generate(9, (i) => i + 1));
      server.dropAtPage = 3;
      final first = await RestoreGymHistory(
        remote: server.phone(),
        sink: sink,
        store: store,
        pageSize: 3,
      )();
      expect(first, isA<Failed<GymHistoryRun>>());
      expect(store.added, greaterThan(0), reason: 'kept across sessions');
      final second = (await restore()())! as Success<GymHistoryRun>;
      expect(second.value.added, 9, reason: 'both parts of the run');
      expect(sink.local, hasLength(9));
    });

    test('once a day it looks again, only after the last position', () async {
      serve([1, 2]);
      await restore()();
      final calls = server.fetchCalls;
      expect(await restore()(), isNull);
      expect(server.fetchCalls, calls, reason: 'not again the same day');

      serve([3]);
      now = now.add(RestoreGymHistory.recheckAfter);
      final again = (await restore()())! as Success<GymHistoryRun>;
      expect(again.value.added, 1);
      expect(sink.local, hasLength(3));
    });

    test('the same workout twice is kept once', () async {
      serve([1, 2]);
      await sink.addBackedUp([workout(1)]);
      final run = (await restore()())! as Success<GymHistoryRun>;
      expect(run.value.added, 1);
      expect(sink.local, hasLength(2));
    });

    test('offline: a failure, nothing changes', () async {
      serve([1]);
      server.dropAtPage = 1;
      expect(await restore()(), isA<Failed<GymHistoryRun>>());
      expect(sink.local, isEmpty);
      expect(((await restore()())! as Success<GymHistoryRun>).value.added, 1);
    });
  });

  group(PrefsGymHistoryCursor, () {
    Future<(PrefsGymHistoryCursor, SharedPreferences)> prefs(
      Map<String, Object> values,
    ) async {
      SharedPreferences.setMockInitialValues(values);
      final p = await SharedPreferences.getInstance();
      return (PrefsGymHistoryCursor(p, now: () => now), p);
    }

    test('done keeps the last position and when', () async {
      final (c, _) = await prefs({});
      await c.write('2026-11-01T10:00:00.000Z|row-1');
      await c.write(RestoreCursor.done);
      expect(c.read(), RestoreCursor.done);
      expect(c.doneAt, now);
      await c.reopen();
      expect(c.read(), '2026-11-01T10:00:00.000Z|row-1');
    });

    test('odd stored values start from the beginning, never fail', () async {
      for (final bad in <Object>[
        'not a cursor',
        'yesterday|row-1',
        '2026-11-01T10:00:00Z|row,1',
        '2026-11-01T10:00:00Z|a)b',
        "2026-11-01T10:00:00Z|x'; drop",
        '2026-11-01T10:00:00Z|${'a' * 100}',
      ]) {
        expect(RestoreCursor.parse(bad as String), isNull, reason: bad);
      }
      final (c, _) = await prefs({
        PrefsGymHistoryCursor.addedKey: -5,
        PrefsGymHistoryCursor.doneAtKey: 'soon',
        PrefsGymHistoryCursor.lastKey: 'nope',
        PrefsGymHistoryCursor.cursorKey: RestoreCursor.done,
      });
      expect(c.added, 0);
      expect(c.doneAt, isNull);
      await c.reopen();
      expect(c.read(), isNull, reason: 'from the beginning');
    });

    test('signing out (the gym state cleared) forgets the position', () async {
      final (c, p) = await prefs({});
      await c.write('2026-11-01T10:00:00.000Z|row-1');
      await c.setAdded(4);
      await PrefsGymLocalRepository(p).clear();
      expect(c.read(), isNull);
      expect(c.added, 0);
      for (final key in PrefsGymHistoryCursor.keys) {
        expect(p.get(key), isNull, reason: key);
      }
    });
  });

  test('network failures stay failures (the next trigger retries)', () {
    expect(const NetworkFailure().isRetryable, isTrue);
  });
}
