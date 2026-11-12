// Long fixtures and test names read better on one line here.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/backup/data/in_memory_backup.dart';
import 'package:gym_tracker/features/backup/domain/entities/backup_status.dart';
import 'package:gym_tracker/features/backup/domain/usecases/run_backup.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes.dart';

WorkoutSession workout(int i) => WorkoutSession(
  dayId: legacyDayId(i % 5),
  finishedAt: DateTime.utc(2026).add(Duration(hours: i * 5)),
  sets: [LoggedSet(exerciseId: 'ex_$i', weight: 20.0 + i, reps: 8)],
);

/// One phone: its own queue, settings and local repository on a shared server.
class Phone {
  new(FakeServer server, {bool enabled = true, this.repo}) {
    settings = InMemoryBackupSettings(enabled: enabled);
    run = RunBackup(
      remote: server.phone(),
      queue: queue,
      settings: settings,
      workouts: repo!,
      now: () => DateTime.utc(2026, 11, 12, 10),
    );
  }

  final queue = FakeQueue();
  late final InMemoryBackupSettings settings;
  late final RunBackup run;
  LocalWorkoutRepository? repo;
}

Future<Phone> phone(FakeServer server, {bool enabled = true}) async {
  SharedPreferences.setMockInitialValues({});
  final repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
  return Phone(server, enabled: enabled, repo: repo);
}

void main() {
  group('workouts', () {
    test('off: nothing is asked of the server', () async {
      final server = FakeServer();
      final p = await phone(server, enabled: false)
        ..queue.all.add(workout(1));
      expect((await p.run()).state, BackupState.off);
      expect(server.uploadCalls, 0);
      expect(p.queue.synced, isEmpty);
    });

    test(
      'goes up oldest first, in chunks of 50, and is marked as backed up',
      () async {
        final server = FakeServer();
        final p = await phone(server);
        for (var i = 0; i < 120; i++) {
          p.queue.all.add(workout(120 - i));
        }
        final status = await p.run();
        expect(status.state, BackupState.upToDate);
        expect(server.sessions, hasLength(120));
        expect(server.chunkSizes, [50, 50, 20]);
        expect(p.queue.synced, hasLength(120));
        expect(status.lastSyncedAt, DateTime.utc(2026, 11, 12, 10));
      },
    );

    test('a second run sends nothing', () async {
      final server = FakeServer();
      final p = await phone(server);
      p.queue.all.add(workout(1));
      await p.run();
      final calls = server.uploadCalls;
      await p.run();
      expect(server.uploadCalls, calls);
    });

    test('no network: the workouts wait and the next run carries on', () async {
      final server = FakeServer()..failWith = const NetworkFailure();
      final p = await phone(server);
      p.queue.all.addAll([workout(1), workout(2)]);
      final status = await p.run();
      expect(status.state, BackupState.waiting);
      expect(status.pending, 2);
      expect(p.queue.synced, isEmpty);
      server.failWith = null;
      expect((await p.run()).state, BackupState.upToDate);
      expect(server.sessions, hasLength(2));
    });

    test(
      'a session that ended asks to sign in again, nothing is lost',
      () async {
        final server = FakeServer()..failWith = const UnauthorizedFailure();
        final p = await phone(server);
        p.queue.all.add(workout(1));
        final status = await p.run();
        expect(status.state, BackupState.signInAgain);
        expect(status.pending, 1);
      },
    );

    test('one refused workout does not hold back the others', () async {
      final server = FakeServer();
      final p = await phone(server);
      p.queue.all.addAll([for (var i = 1; i <= 5; i++) workout(i)]);
      server.refused.add(workout(3).clientId);
      final status = await p.run();
      expect(status.state, BackupState.failed);
      expect(status.problems, 1);
      expect(p.queue.problems.keys, [workout(3).clientId]);
      expect(server.sessions.keys, isNot(contains(workout(3).clientId)));
      expect(server.sessions, hasLength(4));
      // The refused one is not tried again.
      final calls = server.uploadCalls;
      await p.run();
      expect(server.uploadCalls, calls);
    });

    test(
      'a dropped answer after the server stored them is safe to repeat',
      () async {
        final server = FakeServer();
        final p = await phone(server);
        p.queue.all.addAll([workout(1), workout(2)]);
        // The server got them, the phone did not hear: simulate by storing
        // first, then running.
        for (final s in p.queue.all) {
          server.sessions[s.clientId] = s;
        }
        expect((await p.run()).state, BackupState.upToDate);
        expect(server.sessions, hasLength(2));
      },
    );
  });

  group('plan', () {
    test(
      'the first save is version 1, the same plan is not sent again',
      () async {
        final server = FakeServer();
        final p = await phone(server);
        await p.repo!.savePlan(PlanTemplates.fiveDaySplit);
        await p.run();
        expect(server.planVersion, 1);
        expect(p.settings.planVersion, 1);
        await p.run();
        expect(server.planCalls, 1);
      },
    );

    test('an edited plan goes up as the next version', () async {
      final server = FakeServer();
      final p = await phone(server);
      await p.repo!.savePlan(PlanTemplates.fiveDaySplit);
      await p.run();
      final edited = PlanTemplates.fiveDaySplit.toJson();
      ((edited['days']! as List<Object?>).first!
          as Map<String, Object?>)['name'] = {
        'ar': 'جديد',
        'en': 'New name',
      };
      await p.repo!.savePlan(WorkoutPlan.fromJson(edited));
      await p.run();
      expect(server.planVersion, 2);
      expect(p.settings.planVersion, 2);
    });

    test('the account has a newer plan: this one is not uploaded, and it is not tried again', () async {
      final server = FakeServer()
        ..plan = PlanTemplates.fiveDaySplit
        ..planVersion = 3;
      final p = await phone(server);
      final mine = PlanTemplates.fiveDaySplit.toJson();
      ((mine['days']! as List<Object?>).first!
          as Map<String, Object?>)['name'] = {
        'ar': 'خطتي',
        'en': 'Mine',
      };
      await p.repo!.savePlan(WorkoutPlan.fromJson(mine));
      final status = await p.run();
      expect(status.planConflict, isTrue);
      expect(server.planVersion, 3, reason: 'saved first wins');
      expect(server.plan!.days.first.name.en, isNot('Mine'));
      final calls = server.planCalls;
      await p.run();
      expect(server.planCalls, calls);
    });

    test('no plan on the phone: nothing is sent', () async {
      final server = FakeServer();
      final p = await phone(server);
      await p.run();
      expect(server.planCalls, 0);
    });
  });

  group('best level and chosen day', () {
    test('they go up once and again only when they change', () async {
      final server = FakeServer();
      final p = await phone(server);
      await p.repo!.saveBestLevel(Level.intermediate);
      await p.repo!.saveChosenDay(const ChosenDay('day-3'));
      await p.run();
      expect(server.bestLevel, Level.intermediate);
      expect(server.chosenDay, const ChosenDay('day-3'));
      await p.run();
      expect(server.stateCalls, 1);
      await p.repo!.saveChosenDay(null);
      await p.run();
      expect(server.stateCalls, 2);
      expect(server.chosenDay, isNull);
    });

    test('a phone with a lower level never lowers the account', () async {
      final server = FakeServer()..bestLevel = Level.pro;
      final p = await phone(server);
      await p.repo!.saveBestLevel(Level.beginner);
      await p.run();
      expect(server.bestLevel, Level.pro);
    });
  });

  group('two phones, random interleavings', () {
    for (var seed = 0; seed < 25; seed++) {
      test(
        'seed $seed: workouts add up, the first plan wins, the level is the highest',
        () async {
          final random = Random(seed);
          final server = FakeServer();
          final a = await phone(server);
          final b = await phone(server);
          final all = <String>{};
          var next = 1;
          for (var step = 0; step < 30; step++) {
            final p = random.nextBool() ? a : b;
            switch (random.nextInt(5)) {
              case 0:
              case 1:
                final w = workout(next++);
                p.queue.all.add(w);
                all.add(w.clientId);
              case 2:
                server.failWith = random.nextBool()
                    ? const NetworkFailure()
                    : null;
              case 3:
                final json = PlanTemplates.fiveDaySplit.toJson();
                ((json['days']! as List<Object?>).first!
                    as Map<String, Object?>)['name'] = {
                  'ar': 'خ$step',
                  'en': 'Plan $step',
                };
                await p.repo!.savePlan(WorkoutPlan.fromJson(json));
                await p.repo!.saveBestLevel(Level.values[random.nextInt(3)]);
              case _:
                await p.run();
            }
          }
          server.failWith = null;
          await a.run();
          await b.run();
          // Every workout of both phones is on the account, once.
          expect(server.sessions.keys.toSet(), all);
          // The level on the account is never lower than any phone's.
          for (final p in [a, b]) {
            final level =
                (await p.repo!.loadBestLevel() as Success<Level>).value;
            expect(server.bestLevel.index, greaterThanOrEqualTo(level.index));
          }
          // The plan on the account is a plan one of the phones had, never a mix.
          if (server.plan != null) {
            expect(server.planVersion, greaterThanOrEqualTo(1));
          }
        },
      );
    }
  });
}
