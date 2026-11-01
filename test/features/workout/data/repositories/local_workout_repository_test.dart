import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<LocalWorkoutRepository> repo([
  Map<String, Object> values = const {},
]) async {
  SharedPreferences.setMockInitialValues(values);
  return LocalWorkoutRepository(await SharedPreferences.getInstance());
}

T ok<T>(Result<T> r) => switch (r) {
  Success(:final value) => value,
  Failed(:final failure) => fail('expected success, got $failure'),
};

void main() {
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
      dayIndex: 0,
      finishedAt: DateTime.utc(2026, 11, 2, 19),
      sets: const [LoggedSet(exerciseId: 'pec_deck', weight: 40, reps: 10)],
    );
    ok(await r.saveSession(first));
    ok(
      await r.saveSession(
        WorkoutSession(
          dayIndex: 1,
          finishedAt: DateTime.utc(2026, 11, 3),
          sets: const [],
        ),
      ),
    );
    final history = ok(await r.loadHistory());
    expect(history.map((s) => s.dayIndex), [0, 1]);
    expect(history.first.sets.single.weight, 40);
    expect(history.first.finishedAt, first.finishedAt);
  });

  test('keeps at most maxHistory sessions, dropping the oldest', () async {
    final r = await repo();
    for (var i = 0; i < LocalWorkoutRepository.maxHistory + 3; i++) {
      ok(
        await r.saveSession(
          WorkoutSession(
            dayIndex: i % 5,
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
          dayIndex: 0,
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
      ok(await r.saveChosenDay(2));
      expect(ok(await r.loadChosenDay()), 2);
      ok(
        await r.saveSession(
          WorkoutSession(
            dayIndex: 2,
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
}
