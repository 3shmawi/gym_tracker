import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/backup/data/restore_rows.dart';
import 'package:gym_tracker/features/backup/data/supabase_backup_remote.dart';
import 'package:gym_tracker/features/backup/domain/entities/restore.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final _now = DateTime.utc(2026, 11, 12, 10);

Map<String, Object?> row({
  Object? id = 'r1',
  Object? day = 'day-1',
  Object? finished = '2026-11-01T10:00:00+00:00',
  Object? started = '2026-11-01T09:00:00+00:00',
  Object? membership,
  Object? sets = const [
    {'exercise': 'pec_deck', 'weight': 40, 'reps': 10},
  ],
}) => {
  'id': id,
  'gym_id': membership == null ? null : 'd0000000-0000-4000-8000-00000000000a',
  'membership_id': membership,
  'day_id': day,
  'finished_at': finished,
  'started_at': started,
  'sets': sets,
};

void main() {
  group('RestoreRows.session', () {
    test('a good row becomes the workout, with its gym tag and times', () {
      final s = RestoreRows.session(
        row(membership: 'e0000000-0000-4000-8000-000000000003'),
        _now,
      )!;
      expect(s.dayId, 'day-1');
      expect(s.finishedAt, DateTime.utc(2026, 11, 1, 10));
      expect(s.startedAt, DateTime.utc(2026, 11, 1, 9));
      expect(s.membershipId, 'e0000000-0000-4000-8000-000000000003');
      expect(s.sets.single.weight, 40.0);
    });

    test('a bad start time drops the start only, not the workout', () {
      expect(
        RestoreRows.session(
          row(started: '2026-11-02T10:00:00+00:00'),
          _now,
        )!.startedAt,
        isNull,
      );
      expect(
        RestoreRows.session(
          row(started: '2026-10-01T10:00:00+00:00'),
          _now,
        )!.startedAt,
        isNull,
      );
      expect(RestoreRows.session(row(started: null), _now)!.startedAt, isNull);
    });

    for (final (name, bad) in <(String, Map<String, Object?>)>[
      ('a day id with a slash', row(day: 'day/1')),
      ('a day id that is not a string', row(day: 7)),
      ('a day id that is too long', row(day: 'd' * 65)),
      ('no finish time', row(finished: null)),
      ('a finish time that is not a time', row(finished: 'yesterday')),
      ('a finish time before 2020', row(finished: '2019-12-31T23:59:59+00:00')),
      (
        'a finish time a week ahead',
        row(finished: '2026-11-19T10:00:00+00:00'),
      ),
      ('a membership that is not an id', row(membership: '<script>')),
      ('sets that are not a list', row(sets: 'x')),
      ('sets that are null', row(sets: null)),
      ('a set that is not an object', row(sets: const [1])),
      (
        'an exercise id with a space',
        row(
          sets: const [
            {'exercise': 'a b', 'weight': 1, 'reps': 1},
          ],
        ),
      ),
      (
        'a negative weight',
        row(
          sets: const [
            {'exercise': 'x', 'weight': -1, 'reps': 1},
          ],
        ),
      ),
      (
        'a weight over 1000',
        row(
          sets: const [
            {'exercise': 'x', 'weight': 1001, 'reps': 1},
          ],
        ),
      ),
      (
        'a weight that is text',
        row(
          sets: const [
            {'exercise': 'x', 'weight': '5', 'reps': 1},
          ],
        ),
      ),
      (
        'reps that are fractions',
        row(
          sets: const [
            {'exercise': 'x', 'weight': 5, 'reps': 1.5},
          ],
        ),
      ),
      (
        'reps over 1000',
        row(
          sets: const [
            {'exercise': 'x', 'weight': 5, 'reps': 1001},
          ],
        ),
      ),
      (
        'more than 500 sets',
        row(
          sets: [
            for (var i = 0; i < 501; i++)
              {'exercise': 'x', 'weight': 1, 'reps': 1},
          ],
        ),
      ),
    ]) {
      test(
        'refuses $name',
        () => expect(RestoreRows.session(bad, _now), isNull),
      );
    }

    test('a row of the wrong shape never throws', () {
      expect(RestoreRows.session(const {}, _now), isNull);
      expect(RestoreRows.session({'day_id': 1, 'sets': 2}, _now), isNull);
    });
  });

  group('RestoreRows.plan', () {
    test('a good body is a plan; anything else is null', () {
      expect(RestoreRows.plan(PlanTemplates.fiveDaySplit.toJson()), isNotNull);
      expect(RestoreRows.plan(null), isNull);
      expect(RestoreRows.plan('x'), isNull);
      expect(RestoreRows.plan(const {'days': 7}), isNull);
      expect(RestoreRows.plan(const {'days': <Object?>[]}), isNull);
    });
  });

  group('SupabaseBackupRemote restore reads', () {
    SupabaseBackupRemote remote({
      required List<Map<String, Object?>> rows,
      List<(RestoreCursor?, int)>? asked,
      Map<String, Object?>? one,
    }) => SupabaseBackupRemote(
      SupabaseClient('https://abcdefghijklmnopqrst.supabase.co', 'k'),
      retries: 0,
      now: () => _now,
      readSessions: (after, limit) async {
        asked?.add((after, limit));
        return rows;
      },
      readOne: (table) async => one,
    );

    test(
      'a full page has a cursor (the last row), a short one is the end',
      () async {
        final rows = [
          for (var i = 0; i < 4; i++)
            row(id: 'id$i', finished: '2026-11-0${i + 1}T10:00:00+00:00'),
        ];
        final asked = <(RestoreCursor?, int)>[];
        final result = await remote(
          rows: rows,
          asked: asked,
        ).fetchSessions(limit: 3);
        final page = (result as Success<RestorePage>).value;
        expect(
          asked.single.$2,
          4,
          reason: 'one more than the page, to know there is a next one',
        );
        expect(page.sessions, hasLength(3));
        expect(
          page.next,
          const RestoreCursor('2026-11-03T10:00:00+00:00', 'id2'),
        );
        final last = await remote(rows: rows.take(2).toList())
            .fetchSessions(limit: 3);
        expect((last as Success<RestorePage>).value.next, isNull);
      },
    );

    test('the page size never goes past 200', () async {
      final asked = <(RestoreCursor?, int)>[];
      await remote(rows: const [], asked: asked).fetchSessions(limit: 5000);
      expect(asked.single.$2, 201);
    });

    test('unreadable rows are skipped and counted, never an error', () async {
      final rows = [
        row(id: 'a'),
        row(id: 'b', day: 'x/y'),
        row(id: 'c', sets: 'no'),
      ];
      final page =
          ((await remote(rows: rows).fetchSessions()) as Success<RestorePage>)
              .value;
      expect(page.sessions, hasLength(1));
      expect(page.skipped, 2);
    });

    test(
      'a page that cannot be continued is a failure, not a silent end',
      () async {
        final rows = [
          row(id: 'a'),
          row(id: 'b', finished: 'nope'),
          row(id: 'c'),
        ];
        final result = await remote(rows: rows).fetchSessions(limit: 2);
        expect(
          (result as Failed<RestorePage>).failure,
          isA<ValidationFailure>(),
        );
      },
    );

    test(
      'no network is a network failure the restore can resume from',
      () async {
        final r = SupabaseBackupRemote(
          SupabaseClient('https://abcdefghijklmnopqrst.supabase.co', 'k'),
          retries: 0,
          readSessions: (_, _) async => throw AuthRetryableFetchException(),
        );
        expect(
          ((await r.fetchSessions()) as Failed).failure,
          isA<NetworkFailure>(),
        );
      },
    );

    test('the plan and the state of the account', () async {
      final plan = await remote(
        rows: const [],
        one: {'body': PlanTemplates.fiveDaySplit.toJson(), 'version': 3},
      ).fetchPlan();
      expect((plan as Success<RemotePlan?>).value!.version, 3);
      expect(
        ((await remote(rows: const []).fetchPlan()) as Success<RemotePlan?>)
            .value,
        isNull,
      );
      final state = await remote(
        rows: const [],
        one: {
          'best_level': 'pro',
          'chosen_day': {'id': 'day-2'},
        },
      ).fetchState();
      expect((state as Success<RemoteState?>).value!.bestLevel, Level.pro);
      expect(state.value!.chosenDay!.dayId, 'day-2');
    });

    test('a plan the app cannot read is a failure, not a plan', () async {
      for (final one in <Map<String, Object?>>[
        {'body': 'x', 'version': 1},
        {'body': PlanTemplates.fiveDaySplit.toJson(), 'version': 0},
        {'body': PlanTemplates.fiveDaySplit.toJson(), 'version': 'one'},
      ]) {
        final result = await remote(rows: const [], one: one).fetchPlan();
        expect(
          (result as Failed<RemotePlan?>).failure,
          isA<ValidationFailure>(),
          reason: '$one',
        );
      }
    });

    test(
      'a hostile level or chosen day reads as nothing, never a crash',
      () async {
        final state = await remote(
          rows: const [],
          one: {
            'best_level': '<x>',
            'chosen_day': [1],
          },
        ).fetchState();
        final v = (state as Success<RemoteState?>).value!;
        expect(v.bestLevel, Level.beginner);
        expect(v.chosenDay, isNull);
      },
    );
  });
}
