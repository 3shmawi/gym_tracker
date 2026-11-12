// Long fixtures and test names read better on one line here.
// ignore_for_file: lines_longer_than_80_chars

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/backup/data/in_memory_backup.dart';
import 'package:gym_tracker/features/backup/domain/entities/restore.dart';
import 'package:gym_tracker/features/backup/domain/usecases/run_backup.dart';
import 'package:gym_tracker/features/backup/domain/usecases/run_restore.dart';
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

WorkoutPlan renamed(String name) {
  final json = PlanTemplates.fiveDaySplit.toJson();
  ((json['days']! as List<Object?>).first! as Map<String, Object?>)['name'] = {
    'ar': 'س',
    'en': name,
  };
  return WorkoutPlan.fromJson(json);
}

/// A new phone: empty queue, settings and repository on a shared server.
class Phone {
  new _(this.server, this.repo, {int pageSize = 200}) {
    sink = FakeSink(queue);
    restore = RunRestore(
      remote: server.phone(),
      sink: sink,
      settings: settings,
      workouts: repo,
      pageSize: pageSize,
      now: () => DateTime.utc(2026, 11, 12),
    );
    backup = RunBackup(
      remote: server.phone(),
      queue: queue,
      settings: settings,
      workouts: repo,
    );
  }

  static Future<Phone> make(FakeServer server, {int pageSize = 200}) async {
    SharedPreferences.setMockInitialValues({});
    return Phone._(
      server,
      LocalWorkoutRepository(await SharedPreferences.getInstance()),
      pageSize: pageSize,
    );
  }

  final FakeServer server;
  final LocalWorkoutRepository repo;
  final queue = FakeQueue();
  final settings = InMemoryBackupSettings(enabled: true);
  late final FakeSink sink;
  late final RunRestore restore;
  late final RunBackup backup;
}

void main() {
  test(
    'an empty phone gets every workout, once, marked as backed up',
    () async {
      final server = FakeServer();
      for (var i = 1; i <= 7; i++) {
        server.sessions[workout(i).clientId] = workout(i);
      }
      final p = await Phone.make(server, pageSize: 3);
      final result = await p.restore();
      final summary = (result as Success<RestoreSummary>).value;
      expect(summary.sessionsAdded, 7);
      expect(p.sink.local, hasLength(7));
      expect(p.queue.synced, hasLength(7), reason: 'nothing is uploaded again');
      expect(p.settings.restoreCursor, RestoreCursor.done);
      // Oldest first.
      expect(
        [for (final s in p.sink.local) s.finishedAt],
        [for (var i = 1; i <= 7; i++) workout(i).finishedAt],
      );
    },
  );

  test('the account is empty: nothing is added and nothing breaks', () async {
    final p = await Phone.make(FakeServer());
    final summary = ((await p.restore()) as Success<RestoreSummary>).value;
    expect(summary.sessionsAdded, 0);
    expect(summary.plan, isA<PlanNone>());
  });

  test('a dropped connection carries on after the last page taken', () async {
    final server = FakeServer()..dropAtPage = 3;
    for (var i = 1; i <= 9; i++) {
      server.sessions[workout(i).clientId] = workout(i);
    }
    final p = await Phone.make(server, pageSize: 3);
    final first = await p.restore();
    expect(first, isA<Failed<RestoreSummary>>());
    expect(p.sink.local, hasLength(6), reason: 'two pages were kept');
    expect(p.settings.restoreCursor, isNot(RestoreCursor.done));
    expect(RestoreCursor.parse(p.settings.restoreCursor), isNotNull);
    final fetchesBefore = server.fetchCalls;
    final second = ((await p.restore()) as Success<RestoreSummary>).value;
    expect(second.sessionsAdded, 3);
    expect(p.sink.local, hasLength(9));
    expect(
      server.fetchCalls - fetchesBefore,
      1,
      reason: 'only the missing page',
    );
    // A finished restore does not ask for workouts again.
    final calls = server.fetchCalls;
    await p.restore();
    expect(server.fetchCalls, calls);
  });

  test('restoring twice never doubles a workout', () async {
    final server = FakeServer();
    for (var i = 1; i <= 4; i++) {
      server.sessions[workout(i).clientId] = workout(i);
    }
    final p = await Phone.make(server);
    await p.restore();
    p.settings.restoreCursor = null;
    final again = ((await p.restore()) as Success<RestoreSummary>).value;
    expect(again.sessionsAdded, 0);
    expect(p.sink.local, hasLength(4));
  });

  test(
    'rows the app cannot read are counted, not stored, not an error',
    () async {
      final server = FakeServer()..skippedRows = 2;
      server.sessions[workout(1).clientId] = workout(1);
      final p = await Phone.make(server);
      final summary = ((await p.restore()) as Success<RestoreSummary>).value;
      expect(summary.skipped, 2);
      expect(summary.sessionsAdded, 1);
    },
  );

  group('the plan', () {
    test(
      "the phone has none: the account's is taken and not sent back",
      () async {
        final server = FakeServer()
          ..plan = PlanTemplates.fiveDaySplit
          ..planVersion = 4;
        final p = await Phone.make(server);
        final summary = ((await p.restore()) as Success<RestoreSummary>).value;
        expect(summary.plan, isA<PlanTookAccount>());
        expect(
          (await p.repo.loadPlan() as Success<WorkoutPlan?>).value,
          isNotNull,
        );
        expect(p.settings.planVersion, 4);
        await p.backup();
        expect(server.planCalls, 0, reason: "it is the account's plan already");
      },
    );

    test('the same plan on both: nothing changes', () async {
      final server = FakeServer()
        ..plan = PlanTemplates.fiveDaySplit
        ..planVersion = 2;
      final p = await Phone.make(server);
      await p.repo.savePlan(PlanTemplates.fiveDaySplit);
      final summary = ((await p.restore()) as Success<RestoreSummary>).value;
      expect(summary.plan, isA<PlanSame>());
      expect(p.settings.planVersion, 2);
    });

    test(
      'different plans: nothing is changed until the person chooses',
      () async {
        final server = FakeServer()
          ..plan = renamed('Account')
          ..planVersion = 3;
        final p = await Phone.make(server);
        await p.repo.savePlan(renamed('Phone'));
        final summary = ((await p.restore()) as Success<RestoreSummary>).value;
        expect(summary.plan, isA<PlanNeedsChoice>());
        final mine = (await p.repo.loadPlan() as Success<WorkoutPlan?>).value!;
        expect(mine.days.first.name.en, 'Phone');
      },
    );

    test(
      "choosing the account's plan keeps this phone's for 30 days",
      () async {
        final server = FakeServer()
          ..plan = renamed('Account')
          ..planVersion = 3;
        final p = await Phone.make(server);
        await p.repo.savePlan(renamed('Phone'));
        final need =
            (((await p.restore()) as Success<RestoreSummary>).value.plan)
                as PlanNeedsChoice;
        await p.restore.resolvePlan(need, PlanChoice.account);
        final now = (await p.repo.loadPlan() as Success<WorkoutPlan?>).value!;
        expect(now.days.first.name.en, 'Account');
        expect(p.settings.keptPlan, contains('Phone'));
        expect(p.settings.keptPlanAt, DateTime.utc(2026, 11, 12));
        expect(p.settings.planConflict, isFalse);
        await p.backup();
        expect(server.planCalls, 0, reason: 'nothing to upload');
      },
    );

    test("choosing this phone's plan saves it on top of the account's, and keeps the account's for 30 days", () async {
      final server = FakeServer()
        ..plan = renamed('Account')
        ..planVersion = 3;
      final p = await Phone.make(server);
      await p.repo.savePlan(renamed('Phone'));
      final need =
          (((await p.restore()) as Success<RestoreSummary>).value.plan)
              as PlanNeedsChoice;
      await p.restore.resolvePlan(need, PlanChoice.thisPhone);
      expect(p.settings.keptPlan, contains('Account'));
      await p.backup();
      expect(server.planVersion, 4);
      expect(server.plan!.days.first.name.en, 'Phone');
    });
  });

  group('level and chosen day', () {
    test('the higher level wins, in both directions', () async {
      final server = FakeServer()..bestLevel = Level.pro;
      final p = await Phone.make(server);
      await p.repo.saveBestLevel(Level.beginner);
      final summary = ((await p.restore()) as Success<RestoreSummary>).value;
      expect(summary.levelRaised, isTrue);
      expect((await p.repo.loadBestLevel() as Success<Level>).value, Level.pro);

      final low = FakeServer()..bestLevel = Level.intermediate;
      final q = await Phone.make(low);
      await q.repo.saveBestLevel(Level.pro);
      await q.restore();
      expect(
        (await q.repo.loadBestLevel() as Success<Level>).value,
        Level.pro,
        reason: 'never lowered',
      );
    });

    test(
      'the chosen day comes from the account only when the phone has none',
      () async {
        final server = FakeServer()..chosenDay = const ChosenDay('day-3');
        final p = await Phone.make(server);
        final summary = ((await p.restore()) as Success<RestoreSummary>).value;
        expect(summary.chosenDayTaken, isTrue);
        expect(
          (await p.repo.loadChosenDay() as Success<ChosenDay?>).value,
          const ChosenDay('day-3'),
        );

        final q = await Phone.make(server);
        await q.repo.saveChosenDay(const ChosenDay('day-1'));
        final other = ((await q.restore()) as Success<RestoreSummary>).value;
        expect(other.chosenDayTaken, isFalse);
        expect(
          (await q.repo.loadChosenDay() as Success<ChosenDay?>).value,
          const ChosenDay('day-1'),
        );
      },
    );
  });

  test('a failure on the plan or the state is reported and keeps the workouts taken', () async {
    final server = FakeServer();
    server.sessions[workout(1).clientId] = workout(1);
    final p = await Phone.make(server);
    server.failWith = const NetworkFailure();
    expect(await p.restore(), isA<Failed<RestoreSummary>>());
    server.failWith = null;
    final ok = ((await p.restore()) as Success<RestoreSummary>).value;
    expect(ok.sessionsAdded, 1);
  });

  group('lose nothing, whichever phone goes first (random)', () {
    for (var seed = 0; seed < 20; seed++) {
      test(
        'seed $seed: after every phone restores and backs up, all have everything',
        () async {
          final random = Random(seed);
          final server = FakeServer();
          final phones = [
            await Phone.make(server),
            await Phone.make(server),
            await Phone.make(server),
          ];
          final all = <String>{};
          var next = 1;
          for (var step = 0; step < 24; step++) {
            final p = phones[random.nextInt(3)];
            switch (random.nextInt(4)) {
              case 0:
                final w = workout(next++);
                p.sink.local.add(w);
                p.queue.all.add(w);
                all.add(w.clientId);
              case 1:
                server.failWith = random.nextBool()
                    ? const NetworkFailure()
                    : null;
              case 2:
                await p.restore();
              case _:
                await p.backup();
            }
          }
          server.failWith = null;
          for (var round = 0; round < 2; round++) {
            for (final p in phones) {
              p.settings.restoreCursor = null;
              await p.restore();
              await p.backup();
            }
          }
          expect(
            server.sessions.keys.toSet(),
            all,
            reason: 'the account has every workout',
          );
          for (final p in phones) {
            expect(
              {for (final s in p.sink.local) s.clientId},
              all,
              reason: 'every phone has every workout',
            );
          }
        },
      );
    }
  });
}
