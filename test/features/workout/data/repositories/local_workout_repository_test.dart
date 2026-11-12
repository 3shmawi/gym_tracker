import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/data/local/workout_database.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<LocalWorkoutRepository> prefsRepo([
  Map<String, Object> values = const {},
]) async {
  SharedPreferences.setMockInitialValues(values);
  return LocalWorkoutRepository(await SharedPreferences.getInstance());
}

/// The same repository on the phone's database: what `values` holds in the
/// preferences is moved in first, as on a real first start.
Future<LocalWorkoutRepository> databaseRepo([
  Map<String, Object> values = const {},
]) async {
  SharedPreferences.setMockInitialValues(values);
  final db = await WorkoutDatabase.open(
    factory: databaseFactoryFfi,
    path: inMemoryDatabasePath,
    prefs: await SharedPreferences.getInstance(),
  );
  addTearDown(db.close);
  return LocalWorkoutRepository.stores(db.kv, db.sessions);
}

T ok<T>(Result<T> r) => switch (r) {
  Success(:final value) => value,
  Failed(:final failure) => fail('expected success, got $failure'),
};

void main() {
  sqfliteFfiInit();
  // Every behaviour holds on both storages (the database is the default; the
  // preferences are the fallback and the source of the first move).
  suite('preferences', prefsRepo, database: false);
  suite('database', databaseRepo, database: true);
}

void suite(
  String backend,
  Future<LocalWorkoutRepository> Function([Map<String, Object> values]) repo, {
  required bool database,
}) {
  group(backend, () {
    test('no plan yet is null, not an error', () async {
      expect(ok(await (await repo()).loadPlan()), isNull);
      expect(ok(await (await repo()).loadHistory()), isEmpty);
    });

    test('saves and loads the plan', () async {
      final r = await repo();
      ok(await r.savePlan(PlanTemplates.fiveDaySplit));
      final plan = ok(await r.loadPlan())!;
      expect(plan.days, hasLength(5));
      expect(plan.days[1].exercises[4].supersetWithNext, isTrue);
      expect(plan.days[0].exercises.last.name.ar, 'بطن');
    });

    test('appends sessions in order and keeps every set', () async {
      final r = await repo();
      final first = WorkoutSession(
        dayId: legacyDayId(0),
        finishedAt: DateTime.utc(2026, 11, 2, 19),
        sets: const [LoggedSet(exerciseId: 'pec_deck', weight: 40, reps: 10)],
      );
      ok(await r.saveSession(first));
      ok(
        await r.saveSession(
          WorkoutSession(
            dayId: legacyDayId(1),
            finishedAt: DateTime.utc(2026, 11, 3),
            sets: const [],
          ),
        ),
      );
      final history = ok(await r.loadHistory());
      expect(history.map((s) => s.dayId), ['day-1', 'day-2']);
      expect(history.first.sets.single.weight, 40);
      expect(history.first.finishedAt, first.finishedAt);
    });

    test('history has no cap on the database', () async {
      if (!database) return;
      final r = await repo();
      for (var i = 0; i < LocalWorkoutRepository.maxHistory + 3; i++) {
        ok(
          await r.saveSession(
            WorkoutSession(
              dayId: legacyDayId(i % 5),
              finishedAt: DateTime.utc(2026).add(Duration(days: i)),
              sets: const [],
            ),
          ),
        );
      }
      final history = ok(await r.loadHistory());
      expect(history, hasLength(LocalWorkoutRepository.maxHistory + 3));
      expect(history.first.finishedAt, DateTime.utc(2026));
    });

    test('keeps at most maxHistory sessions, dropping the oldest', () async {
      if (database) return;
      final r = await repo();
      for (var i = 0; i < LocalWorkoutRepository.maxHistory + 3; i++) {
        ok(
          await r.saveSession(
            WorkoutSession(
              dayId: legacyDayId(i % 5),
              finishedAt: DateTime.utc(2026).add(Duration(days: i)),
              sets: const [],
            ),
          ),
        );
      }
      final history = ok(await r.loadHistory());
      expect(history, hasLength(LocalWorkoutRepository.maxHistory));
      expect(history.first.finishedAt, DateTime.utc(2026, 1, 4));
    });

    group('corrupt or hostile stored data fails safely', () {
      for (final (name, key, raw) in [
        ('plan not JSON', LocalWorkoutRepository.planKey, '{oops'),
        ('plan is a list', LocalWorkoutRepository.planKey, '[]'),
        ('plan wrong types', LocalWorkoutRepository.planKey, '{"days": 7}'),
        (
          'plan injection-like text',
          LocalWorkoutRepository.planKey,
          '{"days":[{"name":"\'; DROP TABLE plans;--"}]}',
        ),
        ('history not JSON', LocalWorkoutRepository.historyKey, '<script>'),
        ('history is an object', LocalWorkoutRepository.historyKey, '{}'),
        (
          'history wrong types',
          LocalWorkoutRepository.historyKey,
          '[{"day":"one","finished_at":1,"sets":null}]',
        ),
      ]) {
        test(name, () async {
          final r = await repo({key: raw});
          if (database && key == LocalWorkoutRepository.historyKey) {
            // The unreadable text was set aside (quarantine) in the move: the
            // app starts with an empty history, not an error for ever.
            expect(ok(await r.loadHistory()), isEmpty);
            return;
          }
          final result = key == LocalWorkoutRepository.planKey
              ? await r.loadPlan()
              : await r.loadHistory();
          expect(result, isA<Failed<Object?>>());
          expect((result as Failed).failure, isA<ValidationFailure>());
        });
      }
    });

    test('very long names round-trip unchanged', () async {
      final r = await repo();
      final long = 'ب' * 5000;
      ok(
        await r.saveSession(
          WorkoutSession(
            dayId: legacyDayId(0),
            finishedAt: DateTime.utc(2026),
            sets: [LoggedSet(exerciseId: long, weight: 1000000, reps: 999)],
          ),
        ),
      );
      expect(ok(await r.loadHistory()).single.sets.single.exerciseId, long);
    });

    test(
      'chosen day is saved and cleared by the next finished workout',
      () async {
        final r = await repo();
        expect(ok(await r.loadChosenDay()), isNull);
        ok(await r.saveChosenDay(const ChosenDay('day-3')));
        expect(ok(await r.loadChosenDay()), const ChosenDay('day-3'));
        ok(
          await r.saveSession(
            WorkoutSession(
              dayId: legacyDayId(2),
              finishedAt: DateTime.utc(2026),
              sets: const [],
            ),
          ),
        );
        expect(ok(await r.loadChosenDay()), isNull);
      },
    );

    group('best level', () {
      test('beginner until saved, then round-trips', () async {
        final r = await repo();
        expect(ok(await r.loadBestLevel()), Level.beginner);
        ok(await r.saveBestLevel(Level.pro));
        expect(ok(await r.loadBestLevel()), Level.pro);
      });

      for (final (name, Object raw) in [
        ('unknown name', 'legend'),
        ('injection-like text', "pro'; DROP TABLE levels;--"),
        ('wrong type', 3),
        ('huge text', 'pro' * 100000),
      ]) {
        test('$name is a beginner, never a crash', () async {
          final r = await repo({LocalWorkoutRepository.levelKey: raw});
          expect(ok(await r.loadBestLevel()), Level.beginner);
        });
      }
    });

    group('plan editing', () {
      WorkoutPlan oneDay(LocalizedName dayName, [Exercise? e]) => WorkoutPlan(
        days: [
          WorkoutDay(id: 'd1', name: dayName, exercises: [?e]),
        ],
      );

      test('an edited plan round-trips with its day ids', () async {
        final r = await repo();
        final plan = oneDay(
          const LocalizedName(ar: 'صدر', en: 'Chest'),
          const Exercise(
            id: 'ex-1',
            name: LocalizedName(ar: 'بنش', en: 'Bench'),
            targetSets: 4,
            targetReps: 8,
            restSeconds: 120,
            weightStep: 1.25,
          ),
        );
        ok(await r.savePlan(plan));
        final loaded = ok(await r.loadPlan())!;
        expect(loaded.days.single.id, 'd1');
        expect(
          loaded.days.single.exercises.single,
          plan.days.single.exercises.single,
        );
      });

      test('injection-like names are stored as plain text', () async {
        final r = await repo();
        const hostile = LocalizedName(
          ar: "'; DROP TABLE plan;--",
          en: '<script>alert("x")</script>',
        );
        ok(await r.savePlan(oneDay(hostile)));
        expect(ok(await r.loadPlan())!.days.single.name, hostile);
      });

      test('an invalid plan is refused and the old one kept', () async {
        final r = await repo();
        ok(await r.savePlan(PlanTemplates.fiveDaySplit));
        for (final bad in [
          const WorkoutPlan(days: []),
          oneDay(const LocalizedName(ar: '', en: '')),
          oneDay(LocalizedName(ar: 'x' * 41, en: 'x')),
          oneDay(
            const LocalizedName(ar: 'a', en: 'a'),
            const Exercise(
              id: 'e',
              name: LocalizedName(ar: 'a', en: 'a'),
              targetSets: 11,
            ),
          ),
          oneDay(
            const LocalizedName(ar: 'a', en: 'a'),
            const Exercise(
              id: 'e',
              name: LocalizedName(ar: 'a', en: 'a'),
              weightStep: 0,
            ),
          ),
          oneDay(
            const LocalizedName(ar: 'a', en: 'a'),
            const Exercise(
              id: 'e',
              name: LocalizedName(ar: 'a', en: 'a'),
              restSeconds: 601,
            ),
          ),
        ]) {
          final result = await r.savePlan(bad);
          expect(
            result,
            isA<Failed<void>>().having(
              (f) => f.failure,
              'failure',
              isA<ValidationFailure>(),
            ),
          );
        }
        expect(ok(await r.loadPlan())!.days, hasLength(5));
      });
    });

    group('data saved before days had ids', () {
      test('plan days get day-1 … day-n', () async {
        final legacy = PlanTemplates.fiveDaySplit.toJson();
        for (final d in legacy['days']! as List<Object?>) {
          (d! as Map<String, Object?>).remove('id');
        }
        final r = await repo({
          LocalWorkoutRepository.planKey: jsonEncode(legacy),
        });
        final plan = ok(await r.loadPlan())!;
        expect(
          [for (final d in plan.days) d.id],
          ['day-1', 'day-2', 'day-3', 'day-4', 'day-5'],
        );
      });

      test(
        'sessions and the draft map their position to the same ids',
        () async {
          final r = await repo({
            LocalWorkoutRepository.historyKey: jsonEncode([
              {
                'day': 2,
                'finished_at': '2026-11-02T18:00:00.000Z',
                'sets': <Object?>[],
              },
            ]),
            LocalWorkoutRepository.draftKey: jsonEncode({
              'day': 3,
              'started_at': '2026-11-03T18:00:00.000Z',
              'sets': <Object?>[],
            }),
          });
          expect(ok(await r.loadHistory()).single.dayId, 'day-3');
          expect(ok(await r.loadDraft())!.dayId, 'day-4');
        },
      );

      test('the old chosen day (an int) reads as its id', () async {
        final r = await repo({LocalWorkoutRepository.legacyChosenDayKey: 2});
        expect(ok(await r.loadChosenDay()), const ChosenDay('day-3'));
        // Saving a new choice removes the old key.
        ok(await r.saveChosenDay(const ChosenDay('day-1')));
        expect(ok(await r.loadChosenDay()), const ChosenDay('day-1'));
        ok(await r.saveChosenDay(null));
        expect(ok(await r.loadChosenDay()), isNull);
      });

      for (final (name, value) in <(String, Object)>[
        ('a negative old index', -1),
        ('a string old index', 'two'),
      ]) {
        test('$name reads as no choice', () async {
          final r = await repo({
            LocalWorkoutRepository.legacyChosenDayKey: value,
          });
          expect(ok(await r.loadChosenDay()), isNull);
        });
      }
    });

    group('hostile stored chosen day reads as no choice', () {
      for (final (name, raw) in [
        ('not JSON', '{oops'),
        ('a list', '[1,2]'),
        ('no id', '{"by_edit": true}'),
        ('a number id', '{"id": 3}'),
        ('an empty id', '{"id": ""}'),
      ]) {
        test(name, () async {
          final r = await repo({LocalWorkoutRepository.chosenDayKey: raw});
          expect(ok(await r.loadChosenDay()), isNull);
        });
      }

      test('by_edit round-trips', () async {
        final r = await repo();
        ok(await r.saveChosenDay(const ChosenDay('x', byEdit: true)));
        expect(ok(await r.loadChosenDay()), const ChosenDay('x', byEdit: true));
      });
    });
  });
}
