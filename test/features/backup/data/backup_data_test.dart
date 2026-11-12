// Long fixtures and test names read better on one line here.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/backup/data/prefs_backup_settings.dart';
import 'package:gym_tracker/features/backup/data/sqlite_backup_queue.dart';
import 'package:gym_tracker/features/backup/data/supabase_backup_remote.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/data/local/workout_database.dart';
import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

WorkoutSession workout(int i, {String? membershipId}) => WorkoutSession(
  dayId: legacyDayId(i % 5),
  finishedAt: DateTime.utc(2026).add(Duration(hours: i * 5)),
  startedAt: DateTime.utc(2026).add(Duration(hours: i * 5 - 1)),
  membershipId: membershipId,
  sets: [LoggedSet(exerciseId: 'ex_$i', weight: 20.0 + i, reps: 8)],
);

void main() {
  sqfliteFfiInit();

  group('SqliteBackupQueue', () {
    late WorkoutDatabase db;
    late SqliteBackupQueue queue;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = await WorkoutDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
        prefs: await SharedPreferences.getInstance(),
      );
      queue = SqliteBackupQueue(
        db.database,
        now: () => DateTime.utc(2026, 11, 12),
      );
    });
    tearDown(() => db.close());

    test(
      'waiting workouts are the solo ones not yet backed up, oldest first',
      () async {
        await db.sessions.add(workout(3));
        await db.sessions.add(workout(1));
        await db.sessions.add(workout(2, membershipId: 'm1'));
        final pending = await queue.pending(10);
        expect(
          [for (final s in pending) s.dayId],
          [workout(1).dayId, workout(3).dayId],
        );
        expect(await queue.pendingCount(), 2);
      },
    );

    test('the limit is a chunk, the rest wait', () async {
      for (var i = 1; i <= 7; i++) {
        await db.sessions.add(workout(i));
      }
      expect(await queue.pending(3), hasLength(3));
      expect(await queue.pendingCount(), 7);
    });

    test(
      'backed up workouts leave the queue, refused ones are counted and kept',
      () async {
        for (var i = 1; i <= 3; i++) {
          await db.sessions.add(workout(i));
        }
        await queue.markSynced([workout(1).clientId]);
        await queue.markProblem(workout(2).clientId, 'refused');
        expect(
          [for (final s in await queue.pending(10)) s.clientId],
          [workout(3).clientId],
        );
        expect(await queue.problemCount(), 1);
        // Nothing was removed from the phone's history.
        expect(await db.sessions.readAll(), hasLength(3));
      },
    );

    test('workouts moved from the preferences are waiting (the first backup sends them)', () async {
      SharedPreferences.setMockInitialValues({
        'workout.history': jsonEncode([
          workout(1).toJson(),
          workout(2).toJson(),
        ]),
      });
      final moved = await WorkoutDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
        prefs: await SharedPreferences.getInstance(),
      );
      expect(await SqliteBackupQueue(moved.database).pendingCount(), 2);
      await moved.close();
    });

    test('nothing in the queue marks nothing, an empty list is fine', () async {
      await queue.markSynced(const []);
      expect(await queue.pending(5), isEmpty);
    });
  });

  group('PrefsBackupSettings', () {
    test('keeps every value across a restart', () async {
      SharedPreferences.setMockInitialValues({});
      var s = PrefsBackupSettings(await SharedPreferences.getInstance());
      expect(s.enabled, isFalse);
      expect(s.planVersion, 0);
      await s.setEnabled(value: true);
      await s.setLastSyncedAt(DateTime.utc(2026, 11, 12, 9));
      await s.setPlan(version: 4, fingerprint: 'abc');
      await s.setPlanConflict(value: true);
      await s.setStateFingerprint('def');
      s = PrefsBackupSettings(await SharedPreferences.getInstance());
      expect(s.enabled, isTrue);
      expect(s.lastSyncedAt, DateTime.utc(2026, 11, 12, 9));
      expect(s.planVersion, 4);
      expect(s.planFingerprint, 'abc');
      expect(s.planConflict, isTrue);
      expect(s.stateFingerprint, 'def');
    });
  });

  group('SupabaseBackupRemote', () {
    // The client is never used: the seams answer.
    SupabaseBackupRemote remote({
      Future<String?> Function()? person,
      List<List<Map<String, Object?>>>? rows,
      List<(String, Map<String, Object?>?)>? calls,
      Object? Function(String name)? answer,
    }) => SupabaseBackupRemote(
      SupabaseClient('https://abcdefghijklmnopqrst.supabase.co', 'k'),
      retries: 0,
      readPerson: person ?? () async => 'p1',
      insert: (r) async => rows?.add(r),
      call: (name, params) async {
        calls?.add((name, params));
        return answer?.call(name);
      },
    );

    test(
      'a known person is used, an unknown one is made with ensure_person',
      () async {
        final calls = <(String, Map<String, Object?>?)>[];
        final known = remote(calls: calls);
        expect(await known.ensurePerson(), isA<Success<void>>());
        expect(calls, isEmpty);
        final fresh = remote(
          person: () async => null,
          calls: calls,
          answer: (_) => 'p9',
        );
        expect(await fresh.ensurePerson(), isA<Success<void>>());
        expect(calls.single.$1, 'ensure_person');
      },
    );

    test(
      'a refused ensure_person (anonymous) is a failure, not a crash',
      () async {
        final r = SupabaseBackupRemote(
          SupabaseClient('https://abcdefghijklmnopqrst.supabase.co', 'k'),
          retries: 0,
          readPerson: () async => null,
          call: (_, _) async => throw const PostgrestException(
            message: 'forbidden',
            code: '42501',
          ),
        );
        expect(
          ((await r.ensurePerson()) as Failed).failure,
          isA<UnauthorizedFailure>(),
        );
      },
    );

    test(
      'solo workouts go up as rows with no gym and a sane start time',
      () async {
        final rows = <List<Map<String, Object?>>>[];
        final r = remote(rows: rows);
        await r.ensurePerson();
        final weird = WorkoutSession(
          dayId: 'day-1',
          finishedAt: DateTime.utc(2026, 5),
          startedAt: DateTime.utc(2026, 5, 3), // after the end: not sane
          sets: const [],
        );
        expect(
          await r.uploadSessions([workout(1), weird]),
          isA<Success<void>>(),
        );
        final sent = rows.single;
        expect(sent, hasLength(2));
        expect(sent.first.keys.toSet(), {
          'client_id',
          'person_id',
          'day_id',
          'finished_at',
          'started_at',
          'sets',
        });
        expect(sent.first['client_id'], workout(1).clientId);
        expect(sent.first['person_id'], 'p1');
        expect(sent.first.containsKey('gym_id'), isFalse);
        expect(sent.first.containsKey('membership_id'), isFalse);
        expect(sent.last['started_at'], isNull);
      },
    );

    test('more than 50 in one request is refused before it is sent', () async {
      final rows = <List<Map<String, Object?>>>[];
      final r = remote(rows: rows);
      await r.ensurePerson();
      final result = await r.uploadSessions([
        for (var i = 0; i < 51; i++) workout(i),
      ]);
      expect(result, isA<Failed<void>>());
      expect(rows, isEmpty);
    });

    test(
      'the plan goes through save_personal_plan and returns its version',
      () async {
        final calls = <(String, Map<String, Object?>?)>[];
        final r = remote(calls: calls, answer: (_) => {'version': 3});
        final result = await r.savePlan(2, PlanTemplates.fiveDaySplit);
        expect((result as Success<int>).value, 3);
        expect(calls.single.$1, 'save_personal_plan');
        expect(calls.single.$2!['p_base_version'], 2);
        expect(calls.single.$2!['p_body'], PlanTemplates.fiveDaySplit.toJson());
      },
    );

    test('plan_changed is its own failure; a hostile answer is a validation failure', () async {
      final changed = SupabaseBackupRemote(
        SupabaseClient('https://abcdefghijklmnopqrst.supabase.co', 'k'),
        call: (_, _) async => throw const PostgrestException(
          message: 'plan_changed',
          code: 'P0001',
        ),
      );
      expect(
        ((await changed.savePlan(
          0,
          PlanTemplates.fiveDaySplit,
        )) as Failed).failure,
        isA<PlanChangedFailure>(),
      );
      for (final bad in <Object?>[
        null,
        'x',
        {'version': 'one'},
        {'version': 0},
        {'version': -1},
      ]) {
        final r = remote(answer: (_) => bad);
        expect(
          ((await r.savePlan(0, PlanTemplates.fiveDaySplit)) as Failed).failure,
          isA<ValidationFailure>(),
          reason: '$bad',
        );
      }
    });

    test(
      'the state goes through save_personal_state, the cap is not retried',
      () async {
        final calls = <(String, Map<String, Object?>?)>[];
        final r = remote(calls: calls);
        await r.saveState(Level.pro, const ChosenDay('day-2', byEdit: true));
        expect(calls.single.$1, 'save_personal_state');
        expect(calls.single.$2, {
          'p_best_level': 'pro',
          'p_chosen_day': {'id': 'day-2', 'by_edit': true},
        });
        final capped = SupabaseBackupRemote(
          SupabaseClient('https://abcdefghijklmnopqrst.supabase.co', 'k'),
          insert: (_) async => throw const PostgrestException(
            message: 'too_many_workouts',
            code: '54000',
          ),
          readPerson: () async => 'p1',
        );
        await capped.ensurePerson();
        final result = await capped.uploadSessions([workout(1)]);
        expect((result as Failed).failure, isA<ValidationFailure>());
        expect(result.failure.isRetryable, isFalse);
      },
    );
  });

  group('SqliteSessionStore as the restore sink', () {
    late WorkoutDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = await WorkoutDatabase.open(
        factory: databaseFactoryFfi,
        path: inMemoryDatabasePath,
        prefs: await SharedPreferences.getInstance(),
      );
    });
    tearDown(() => db.close());

    test(
      'restored workouts are in the history, marked as backed up, never twice',
      () async {
        expect(await db.sessions.addBackedUp([workout(1), workout(2)]), 2);
        expect(await db.sessions.addBackedUp([workout(2), workout(3)]), 1);
        expect(await db.sessions.count(), 3);
        expect(await db.sessions.readAll(), hasLength(3));
        final queue = SqliteBackupQueue(db.database);
        expect(
          await queue.pendingCount(),
          0,
          reason: 'they are not uploaded again',
        );
      },
    );

    test('a workout the phone already has stays as it was (still waiting if it was)', () async {
      await db.sessions.add(workout(1));
      expect(await db.sessions.addBackedUp([workout(1)]), 0);
      final queue = SqliteBackupQueue(db.database);
      expect(await queue.pendingCount(), 1);
    });

    test('the gym tag comes back with the workout', () async {
      await db.sessions.addBackedUp([workout(1, membershipId: 'm-1')]);
      final all = await db.sessions.readAll();
      expect(all.single.membershipId, 'm-1');
      // A gym workout is not in the solo queue.
      expect(await SqliteBackupQueue(db.database).pendingCount(), 0);
    });

    test(
      'the history shows restored workouts at once (no stale copy)',
      () async {
        await db.sessions.add(workout(5));
        expect(await db.sessions.readAll(), hasLength(1));
        await db.sessions.addBackedUp([workout(1)]);
        final all = await db.sessions.readAll();
        expect(all, hasLength(2));
        expect(
          all.first.finishedAt,
          workout(1).finishedAt,
          reason: 'oldest first',
        );
      },
    );

    test('an empty list does nothing', () async {
      expect(await db.sessions.addBackedUp(const []), 0);
    });
  });
}
