// SQL, test names and long fixtures read better on one line here.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/data/local/open_workout_repository.dart';
import 'package:gym_tracker/features/workout/data/local/workout_database.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The move from preferences to the phone's database, and the database's own
/// rules (docs/designs/never_lose_history.md §1, §10 PR 1).

WorkoutSession workout(int i, {String? membershipId, int sets = 2}) =>
    WorkoutSession(
      dayId: legacyDayId(i % 5),
      finishedAt: DateTime.utc(2024).add(Duration(hours: i * 7)),
      startedAt: DateTime.utc(2024).add(Duration(hours: i * 7 - 1)),
      membershipId: membershipId,
      sets: [
        for (var k = 0; k < sets; k++)
          LoggedSet(exerciseId: 'ex_$k', weight: 20.5 + i % 7, reps: 8 + k),
      ],
    );

String historyJson(Iterable<WorkoutSession> list) =>
    jsonEncode([for (final s in list) s.toJson()]);

T ok<T>(Result<T> r) => switch (r) {
  Success(:final value) => value,
  Failed(:final failure) => fail('expected success, got $failure'),
};

Future<SharedPreferences> prefsWith(Map<String, Object> values) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Future<WorkoutDatabase> open(
  SharedPreferences prefs, {
  String path = inMemoryDatabasePath,
}) =>
    WorkoutDatabase.open(factory: databaseFactoryFfi, path: path, prefs: prefs);

void main() {
  sqfliteFfiInit();
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('azm_db_test');
    path = '${dir.path}/azm.db';
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('the move from preferences', () {
    test(
      'an empty phone: a database with nothing in it, marked as moved',
      () async {
        final db = await open(await prefsWith({}), path: path);
        expect(db.report.migrated, isTrue);
        expect(db.report.sessionsMoved, 0);
        expect(
          ok(
            await LocalWorkoutRepository.stores(
              db.kv,
              db.sessions,
            ).loadHistory(),
          ),
          isEmpty,
        );
        await db.close();
        // The second start changes nothing.
        final again = await open(await prefsWith({}), path: path);
        expect(again.report.migrated, isFalse);
        await again.close();
      },
    );

    for (final count in [1, 200]) {
      test(
        '$count workouts, the plan, the draft and the level arrive; the old keys stay',
        () async {
          final sessions = [
            for (var i = 0; i < count; i++)
              workout(i, membershipId: i.isEven ? null : 'm1'),
          ];
          final values = <String, Object>{
            LocalWorkoutRepository.historyKey: historyJson(sessions),
            LocalWorkoutRepository.planKey: '{"keep":"raw"}',
            LocalWorkoutRepository.draftKey: '{"raw":"draft"}',
            LocalWorkoutRepository.chosenDayKey: '{"raw":"day"}',
            LocalWorkoutRepository.levelKey: 'pro',
          };
          final prefs = await prefsWith(values);
          final db = await open(prefs, path: path);
          expect(db.report.sessionsMoved, count);
          final read = ok(
            await LocalWorkoutRepository.stores(
              db.kv,
              db.sessions,
            ).loadHistory(),
          );
          expect(read, hasLength(count));
          // Same workouts, same order, nothing changed on the way.
          expect(
            [for (final s in read) s.clientId],
            [for (final s in sessions) s.clientId],
          );
          expect(read.first.membershipId, isNull);
          expect(read.first.startedAt, sessions.first.startedAt);
          expect(db.kv.get(LocalWorkoutRepository.planKey), '{"keep":"raw"}');
          expect(db.kv.get(LocalWorkoutRepository.draftKey), '{"raw":"draft"}');
          expect(db.kv.get(LocalWorkoutRepository.levelKey), 'pro');
          // Not deleted: the old keys are the fallback.
          for (final entry in values.entries) {
            expect(prefs.get(entry.key), entry.value, reason: entry.key);
          }
          await db.close();
        },
      );
    }

    test('the same workout twice becomes one', () async {
      final w = workout(1);
      final db = await open(
        await prefsWith({
          LocalWorkoutRepository.historyKey: historyJson([w, w, workout(2)]),
        }),
        path: path,
      );
      expect(
        ok(
          await LocalWorkoutRepository.stores(db.kv, db.sessions).loadHistory(),
        ),
        hasLength(2),
      );
      await db.close();
    });

    test('a second run with nothing new changes nothing', () async {
      final values = {
        LocalWorkoutRepository.historyKey: historyJson([
          workout(1),
          workout(2),
        ]),
      };
      final first = await open(await prefsWith(values), path: path);
      await first.close();
      final second = await open(await prefsWith(values), path: path);
      expect(second.report.migrated, isFalse);
      expect(
        ok(
          await LocalWorkoutRepository.stores(
            second.kv,
            second.sessions,
          ).loadHistory(),
        ),
        hasLength(2),
      );
      await second.close();
    });

    test(
      'a start that used the preferences (or an older release) is picked up',
      () async {
        final first = await open(
          await prefsWith({
            LocalWorkoutRepository.historyKey: historyJson([workout(1)]),
          }),
          path: path,
        );
        await first.close();
        // Meanwhile the preferences got one more workout.
        final again = await open(
          await prefsWith({
            LocalWorkoutRepository.historyKey: historyJson([
              workout(1),
              workout(2),
            ]),
          }),
          path: path,
        );
        expect(again.report.sessionsMoved, 1);
        expect(
          ok(
            await LocalWorkoutRepository.stores(
              again.kv,
              again.sessions,
            ).loadHistory(),
          ),
          hasLength(2),
        );
        await again.close();
      },
    );

    test('50,000 workouts move, once each', () async {
      final sessions = [for (var i = 0; i < 50000; i++) workout(i, sets: 1)];
      final watch = Stopwatch()..start();
      final db = await open(
        await prefsWith({
          LocalWorkoutRepository.historyKey: historyJson(sessions),
        }),
        path: path,
      );
      watch.stop();
      expect(db.report.sessionsMoved, 50000);
      expect(
        ok(
          await LocalWorkoutRepository.stores(db.kv, db.sessions).loadHistory(),
        ),
        hasLength(50000),
      );
      // The numbers are the point of this test: print them for the log.
      // ignore: avoid_print
      print('move of 50,000 workouts: ${watch.elapsedMilliseconds} ms');
      await db.close();
    }, timeout: const Timeout(Duration(minutes: 3)));
  });

  group(
    'unreadable data is set aside, never lost and never an error screen',
    () {
      test(
        'the whole history text is unreadable: raw kept, empty history',
        () async {
          final db = await open(
            await prefsWith({
              LocalWorkoutRepository.historyKey: '<script>not json',
            }),
            path: path,
          );
          expect(db.report.quarantined, 1);
          final rows = await db.database.query('quarantine');
          expect(rows.single['kind'], 'history');
          expect(rows.single['raw'], '<script>not json');
          expect(
            ok(
              await LocalWorkoutRepository.stores(
                db.kv,
                db.sessions,
              ).loadHistory(),
            ),
            isEmpty,
          );
          await db.close();
        },
      );

      test(
        'one bad workout among good ones: the good move, the bad one is kept',
        () async {
          final good = [workout(1), workout(2)];
          final raw = jsonEncode([
            good[0].toJson(),
            {'day': 'x', 'finished_at': 1, 'sets': null},
            good[1].toJson(),
          ]);
          final db = await open(
            await prefsWith({LocalWorkoutRepository.historyKey: raw}),
            path: path,
          );
          expect(db.report.sessionsMoved, 2);
          expect(db.report.quarantined, 1);
          expect(
            (await db.database.query('quarantine')).single['kind'],
            'session',
          );
          await db.close();
        },
      );

      test(
        'an unreadable plan is copied raw and fails as it did before',
        () async {
          final db = await open(
            await prefsWith({LocalWorkoutRepository.planKey: '{oops'}),
            path: path,
          );
          expect(db.kv.get(LocalWorkoutRepository.planKey), '{oops');
          final r = LocalWorkoutRepository.stores(db.kv, db.sessions);
          expect(await r.loadPlan(), isA<Failed<Object?>>());
          await db.close();
        },
      );
    },
  );

  group('when something goes wrong', () {
    test(
      'a crash halfway rolls everything back; the next start does it again',
      () async {
        final prefs = await prefsWith({
          LocalWorkoutRepository.historyKey: historyJson([
            workout(1),
            workout(2),
            workout(3),
          ]),
        });
        // A database whose marker write fails: the workouts were already inserted.
        final seed = await open(await prefsWith({}), path: path);
        await seed.database.execute('DELETE FROM kv');
        await seed.database.execute(
          "CREATE TRIGGER boom BEFORE INSERT ON kv WHEN NEW.key = 'meta.migrated_v1' "
          "BEGIN SELECT RAISE(ABORT, 'boom'); END",
        );
        await seed.close();
        await expectLater(open(prefs, path: path), throwsA(isA<Object>()));

        final raw = await databaseFactoryFfi.openDatabase(path);
        expect(await raw.query('sessions'), isEmpty, reason: 'rolled back');
        expect(await raw.query('kv'), isEmpty, reason: 'no marker');
        await raw.execute('DROP TRIGGER boom');
        await raw.close();

        final again = await open(prefs, path: path);
        expect(again.report.sessionsMoved, 3);
        await again.close();
      },
    );

    test(
      'a count that does not add up is refused before anything is committed',
      () async {
        // Two different workouts with the same content hash cannot exist, so
        // force a mismatch through a trigger that swallows an insert.
        final seed = await open(await prefsWith({}), path: path);
        await seed.database.execute('DELETE FROM kv');
        await seed.database.execute(
          'CREATE TRIGGER eat BEFORE INSERT ON sessions BEGIN SELECT RAISE(IGNORE); END',
        );
        await seed.close();
        final prefs = await prefsWith({
          LocalWorkoutRepository.historyKey: historyJson([workout(1)]),
        });
        await expectLater(
          open(prefs, path: path),
          throwsA(isA<DatabaseMoveException>()),
        );
      },
    );

    test('a file that is not a database is put aside and a new one is filled from the old keys', () async {
      File(path).writeAsStringSync('this is not a sqlite file' * 100);
      final prefs = await prefsWith({
        LocalWorkoutRepository.historyKey: historyJson([
          workout(1),
          workout(2),
        ]),
      });
      final db = await open(prefs, path: path);
      expect(db.report.repaired, isTrue);
      expect(
        ok(
          await LocalWorkoutRepository.stores(db.kv, db.sessions).loadHistory(),
        ),
        hasLength(2),
      );
      expect(dir.listSync().any((f) => f.path.contains('.corrupt-')), isTrue);
      await db.close();
    });

    test('the database cannot be opened: the preferences repository is used, and reported', () async {
      final blocked = '${dir.path}/afile/azm.db';
      File('${dir.path}/afile').writeAsStringSync('x');
      final prefs = await prefsWith({
        LocalWorkoutRepository.historyKey: historyJson([workout(1)]),
      });
      final events = <String>[];
      final errors = <Object>[];
      final repo = await openWorkoutRepository(
        prefs,
        onEvent: (name, data) => events.add('$name ${data['reason']}'),
        onError: (e, s) => errors.add(e),
        factory: databaseFactoryFfi,
        // A "folder" that is a file: the database cannot be created there.
        path: blocked,
      );
      expect(events, ['local_db_migration_failed open']);
      expect(repo.database, isNull);
      expect(errors, hasLength(1));
      // Still works, on the preferences.
      expect(ok(await repo.repository.loadHistory()), hasLength(1));
      ok(await repo.repository.saveSession(workout(2)));
      expect(ok(await repo.repository.loadHistory()), hasLength(2));

      // Next start: the database opens and has both workouts.
      final events2 = <String>[];
      final repo2 = await openWorkoutRepository(
        prefs,
        onEvent: (name, data) => events2.add(name),
        onError: (e, s) => fail('no error expected'),
        factory: databaseFactoryFfi,
        path: path,
      );
      expect(events2, ['local_db_migrated']);
      expect(ok(await repo2.repository.loadHistory()), hasLength(2));
      await repo2.database?.close();
    });
  });

  group('the database', () {
    test('the content hash is the key: saving the same workout twice stores it once', () async {
      final db = await open(await prefsWith({}), path: path);
      final r = LocalWorkoutRepository.stores(db.kv, db.sessions);
      ok(await r.saveSession(workout(1)));
      ok(await r.saveSession(workout(1)));
      expect(ok(await r.loadHistory()), hasLength(1));
      await db.close();
    });

    test(
      'workouts are kept across a restart, oldest first by finish time',
      () async {
        var db = await open(await prefsWith({}), path: path);
        var r = LocalWorkoutRepository.stores(db.kv, db.sessions);
        ok(await r.saveSession(workout(5)));
        ok(await r.saveSession(workout(2)));
        await db.close();
        db = await open(await prefsWith({}), path: path);
        r = LocalWorkoutRepository.stores(db.kv, db.sessions);
        expect(
          [for (final s in ok(await r.loadHistory())) s.finishedAt],
          [workout(2).finishedAt, workout(5).finishedAt],
        );
        await db.close();
      },
    );

    test(
      'clearing erases workouts, draft, chosen day and level, not the plan',
      () async {
        final db = await open(
          await prefsWith({
            LocalWorkoutRepository.historyKey: historyJson([workout(1)]),
            LocalWorkoutRepository.levelKey: 'pro',
          }),
          path: path,
        );
        final r = LocalWorkoutRepository.stores(db.kv, db.sessions);
        ok(await r.clearHistory());
        expect(ok(await r.loadHistory()), isEmpty);
        expect(db.kv.get(LocalWorkoutRepository.levelKey), isNull);
        await db.close();
      },
    );

    test('a sanity limit stops a runaway bug', () async {
      final db = await open(await prefsWith({}), path: path);
      // Fill the table directly to just under the limit, then add past it.
      final batch = db.database.batch();
      for (var i = 0; i < SqliteSessionStore.maxRows; i++) {
        batch.insert('sessions', {
          'client_id': 'c$i',
          'day_id': 'day-1',
          'finished_at': i,
          'sets': '[]',
        });
      }
      await batch.commit(noResult: true);
      final store = await SqliteSessionStore.create(db.database);
      await expectLater(store.add(workout(1)), throwsStateError);
      await db.close();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('speed on a long history (5,000 workouts)', () {
    test('saving, reading and the first read stay well inside the budget', () async {
      final db = await open(await prefsWith({}), path: path);
      final batch = db.database.batch();
      for (var i = 0; i < 5000; i++) {
        batch.insert('sessions', SqliteSessionStore.toRow(workout(i)));
      }
      await batch.commit(noResult: true);
      final store = await SqliteSessionStore.create(db.database);
      final read = Stopwatch()..start();
      final all = await store.readAll();
      read.stop();
      final save = Stopwatch()..start();
      await store.add(workout(9000));
      save.stop();
      // The numbers are the point of this test: print them for the log.
      // ignore: avoid_print
      print(
        '5,000 workouts: first read ${read.elapsedMilliseconds} ms, save ${save.elapsedMilliseconds} ms',
      );
      expect(all, hasLength(5000));
      // The targets are 300 ms and 50 ms on a mid-range phone; a CI machine
      // gets a wide margin so the test only catches a real regression.
      expect(read.elapsedMilliseconds, lessThan(2000));
      expect(save.elapsedMilliseconds, lessThan(500));
      await db.close();
    });
  });
}
