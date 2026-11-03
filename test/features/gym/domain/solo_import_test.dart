import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/data/repositories/in_memory_solo_import.dart';
import 'package:gym_tracker/features/gym/domain/entities/solo_import.dart';
import 'package:gym_tracker/features/gym/domain/usecases/import_solo_data.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../helpers/solo_fakes.dart';

WorkoutSession session({
  String day = 'day-1',
  DateTime? at,
  List<LoggedSet> sets = const [
    LoggedSet(exerciseId: 'bench', weight: 50, reps: 12),
  ],
}) => WorkoutSession(
  dayId: day,
  finishedAt: at ?? DateTime.utc(2026, 10, 1, 9),
  sets: sets,
);

void main() {
  final now = DateTime.utc(2026, 11, 2);

  group('ImportSession', () {
    test('client_id is a stable sha256 of day|finished_at|sets', () {
      final a = ImportSession.fromSession(session());
      final b = ImportSession.fromSession(session());
      expect(a.clientId, b.clientId);
      expect(a.clientId, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(a.finishedAt, '2026-10-01T09:00:00.000Z');
    });

    test('any change in the workout changes its id', () {
      final base = ImportSession.fromSession(session()).clientId;
      expect(
        ImportSession.fromSession(session(day: 'day-2')).clientId,
        isNot(base),
      );
      expect(
        ImportSession.fromSession(session(at: DateTime.utc(2026, 10, 1, 9, 1)))
            .clientId,
        isNot(base),
      );
      expect(
        ImportSession.fromSession(
          session(
            sets: const [
              LoggedSet(exerciseId: 'bench', weight: 52.5, reps: 12),
            ],
          ),
        ).clientId,
        isNot(base),
      );
    });

    test('the same instant in another time zone is the same workout', () {
      final local = session(at: DateTime.utc(2026, 10, 1, 9));
      final other = session(at: DateTime.parse('2026-10-01T11:00:00+02:00'));
      expect(
        ImportSession.fromSession(local).clientId,
        ImportSession.fromSession(other).clientId,
      );
    });

    test('mirrors what the server refuses', () {
      String? p(WorkoutSession s) => ImportSession.problemWith(s, now: now);
      expect(p(session()), isNull);
      expect(p(session(day: 'bad day!')), isNotNull);
      expect(p(session(day: '')), isNotNull);
      expect(p(session(at: DateTime.utc(2019, 12, 31))), isNotNull);
      expect(p(session(at: now.add(const Duration(days: 2)))), isNotNull);
      expect(
        p(
          session(
            sets: const [LoggedSet(exerciseId: 'a b', weight: 1, reps: 1)],
          ),
        ),
        isNotNull,
      );
      expect(
        p(
          session(
            sets: const [LoggedSet(exerciseId: 'a', weight: 1001, reps: 1)],
          ),
        ),
        isNotNull,
      );
      expect(
        p(
          session(
            sets: const [LoggedSet(exerciseId: 'a', weight: -1, reps: 1)],
          ),
        ),
        isNotNull,
      );
      expect(
        p(
          session(
            sets: const [LoggedSet(exerciseId: 'a', weight: 1, reps: 1001)],
          ),
        ),
        isNotNull,
      );
      expect(
        p(
          session(
            sets: [
              for (var i = 0; i < 501; i++)
                const LoggedSet(exerciseId: 'a', weight: 1, reps: 1),
            ],
          ),
        ),
        isNotNull,
      );
    });
  });

  group('ImportAck', () {
    test('reads the server answer and refuses odd ones', () {
      final ack = ImportAck.fromJson(const {
        'imported': 3,
        'skipped': 1,
        'plan_saved': true,
        'solo_total': 9,
      });
      expect(
        [ack.imported, ack.skipped, ack.planSaved, ack.soloTotal],
        [3, 1, true, 9],
      );
      for (final bad in <Object?>[
        null,
        'x',
        <String, Object?>{},
        {'imported': -1, 'skipped': 0, 'solo_total': 0},
      ]) {
        expect(() => ImportAck.fromJson(bad), throwsFormatException);
      }
    });
  });

  group('ImportSoloData', () {
    late SharedPreferences prefs;
    late LocalWorkoutRepository workouts;
    late InMemorySoloImportStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      workouts = LocalWorkoutRepository(prefs);
      store = InMemorySoloImportStore();
    });

    Future<void> seed(List<WorkoutSession> sessions, {bool plan = true}) async {
      if (plan) await workouts.savePlan(PlanTemplates.fiveDaySplit);
      for (final s in sessions) {
        await workouts.saveSession(s);
      }
    }

    ImportSoloData usecase(FakeSoloServer server) => ImportSoloData(
      FindSoloData(workouts, now: () => now),
      server,
      store,
      workouts,
    );

    test('copies in chunks of 50, plan first, and marks done', () async {
      await seed([
        for (var i = 0; i < 120; i++)
          session(at: DateTime.utc(2026).add(Duration(hours: i))),
      ]);
      final server = FakeSoloServer();
      final progress = <(int, int)>[];
      final result = await usecase(server)(
        onProgress: (d, t) => progress.add((d, t)),
      );

      expect(result, isA<Success<SoloImportStatus>>());
      expect(server.stored, hasLength(120));
      expect(server.calls, 3, reason: '50 + 50 + 20');
      expect(server.plan, isNotNull);
      expect(progress.last, (120, 120));
      expect(store.status.choice, SoloImportChoice.done);
      expect(store.status.migratedAt, isNotNull);
    });

    test('the phone keeps every workout and its plan', () async {
      await seed([session(), session(at: DateTime.utc(2026, 10, 2))]);
      await usecase(FakeSoloServer())();
      final history =
          (await workouts.loadHistory() as Success<List<WorkoutSession>>).value;
      expect(history, hasLength(2));
      expect((await workouts.loadPlan() as Success).value, isNotNull);
    });

    test('a plan with no workouts is still sent', () async {
      await seed([]);
      final server = FakeSoloServer();
      await usecase(server)();
      expect(server.calls, 1);
      expect(server.plan, isNotNull);
    });

    test('the server never gets a chunk it would refuse', () async {
      await seed([
        session(),
        session(),
        session(at: DateTime.utc(2019)),
        session(day: 'bad day'),
      ]);
      final server = FakeSoloServer();
      final result = await usecase(server)();
      expect(result, isA<Success<SoloImportStatus>>());
      expect(server.refusedChunks, 0);
      expect(server.stored, hasLength(1), reason: 'one valid, deduplicated');
    });

    test('offline: the failure comes back, nothing is marked done', () async {
      await seed([session()]);
      final server = FakeSoloServer()..script.add('before');
      final result = await usecase(server)();
      expect(
        (result as Failed<SoloImportStatus>).failure,
        isA<NetworkFailure>(),
      );
      expect(store.status.choice, SoloImportChoice.copying);
      expect(store.status.migratedAt, isNull);
    });

    test(
      'a lost answer: the retry is safe and ends with the same data',
      () async {
        await seed([
          for (var i = 0; i < 70; i++)
            session(at: DateTime.utc(2026).add(Duration(hours: i))),
        ]);
        final server = FakeSoloServer()..script.addAll(['none', 'after']);
        final first = await usecase(server)();
        expect(first, isA<Failed<SoloImportStatus>>());
        final second = await usecase(server)();
        expect(second, isA<Success<SoloImportStatus>>());
        expect(server.stored, hasLength(70));
      },
    );

    test('not done until the server total covers what was sent', () async {
      await seed([session(), session(at: DateTime.utc(2026, 10, 3))]);
      final lying = _ShortServer();
      final result = await ImportSoloData(
        FindSoloData(workouts, now: () => now),
        lying,
        store,
        workouts,
      )();
      expect(result, isA<Failed<SoloImportStatus>>());
      expect(store.status.choice, isNot(SoloImportChoice.done));
    });

    test(
      'random histories, random interruptions: nothing lost, nothing doubled',
      () async {
        for (var seed0 = 0; seed0 < 40; seed0++) {
          SharedPreferences.setMockInitialValues({});
          final p = await SharedPreferences.getInstance();
          final repo = LocalWorkoutRepository(p);
          final rnd = Random(seed0);
          final history = randomHistory(rnd);
          await repo.savePlan(PlanTemplates.fiveDaySplit);
          // Saving trims to 200; use what the phone really kept.
          for (final s in history) {
            await repo.saveSession(s);
          }
          final kept =
              (await repo.loadHistory() as Success<List<WorkoutSession>>).value;
          final expected = {
            for (final s in kept)
              if (ImportSession.problemWith(s, now: now) == null)
                ImportSession.fromSession(s).clientId,
          };
          final st = InMemorySoloImportStore();
          final server = FakeSoloServer(random: rnd, failRate: 0.35);
          final run = ImportSoloData(
            FindSoloData(repo, now: () => now),
            server,
            st,
            repo,
          );
          Result<SoloImportStatus>? last;
          for (var attempt = 0; attempt < 60; attempt++) {
            last = await run();
            if (last is Success) break;
          }
          expect(last, isA<Success<SoloImportStatus>>(), reason: 'seed $seed0');
          expect(server.stored.keys.toSet(), expected, reason: 'seed $seed0');
          expect(server.refusedChunks, 0, reason: 'seed $seed0');
          expect(server.plan, isNotNull, reason: 'seed $seed0');
          // The phone still has everything it had.
          final after =
              (await repo.loadHistory() as Success<List<WorkoutSession>>).value;
          expect(after.length, kept.length, reason: 'seed $seed0');
          // Running again changes nothing (idempotent).
          final before = server.stored.length;
          await run();
          expect(server.stored.length, before, reason: 'seed $seed0');
        }
      },
    );
  });
}

class _ShortServer extends FakeSoloServer {
  @override
  Future<Result<ImportAck>> importChunk(
    List<ImportSession> sessions, {
    WorkoutPlan? plan,
  }) async => const Success(
    ImportAck(imported: 0, skipped: 0, planSaved: false, soloTotal: 0),
  );
}
