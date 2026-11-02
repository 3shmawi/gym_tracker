import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/chosen_day.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_draft.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';
import 'package:gym_tracker/features/workout/domain/usecases/edit_plan.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/plan_editor_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fails saving the plan [saveFailures] times, then delegates.
class _FailingSaves implements WorkoutRepository {
  new(this._inner);

  final WorkoutRepository _inner;
  int saveFailures = 1;
  bool failLoad = false;

  @override
  Future<Result<void>> savePlan(WorkoutPlan plan) async {
    if (saveFailures > 0) {
      saveFailures--;
      return const Failed(UnknownFailure('disk full'));
    }
    return await _inner.savePlan(plan);
  }

  @override
  Future<Result<WorkoutPlan?>> loadPlan() async =>
      failLoad ? const Failed(ValidationFailure()) : await _inner.loadPlan();

  @override
  Future<Result<List<WorkoutSession>>> loadHistory() => _inner.loadHistory();
  @override
  Future<Result<void>> saveSession(WorkoutSession s) => _inner.saveSession(s);
  @override
  Future<Result<ChosenDay?>> loadChosenDay() => _inner.loadChosenDay();
  @override
  Future<Result<void>> saveChosenDay(ChosenDay? d) => _inner.saveChosenDay(d);
  @override
  Future<Result<WorkoutDraft?>> loadDraft() => _inner.loadDraft();
  @override
  Future<Result<void>> saveDraft(WorkoutDraft? d) => _inner.saveDraft(d);
  @override
  Future<Result<Level>> loadBestLevel() => _inner.loadBestLevel();
  @override
  Future<Result<void>> saveBestLevel(Level l) => _inner.saveBestLevel(l);
  @override
  Future<Result<void>> clearHistory() => _inner.clearHistory();
}

const _chest = LocalizedName(ar: 'صدر', en: 'Chest');
const _bench = LocalizedName(ar: 'بنش', en: 'Bench');
const _fly = LocalizedName(ar: 'فراشة', en: 'Fly');

T _ok<T>(Result<T> r) => (r as Success<T>).value;

void main() {
  late LocalWorkoutRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
  });

  ProviderContainer container(WorkoutRepository r) {
    final c = ProviderContainer(
      overrides: [
        workoutRepositoryProvider.overrideWithValue(r),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 5, 18)),
      ],
    );
    addTearDown(c.dispose);
    // Keep the auto-disposed editor alive for the test.
    c.listen(planEditorControllerProvider, (_, _) {});
    return c;
  }

  Future<PlanEditorController> editor(ProviderContainer c) => c
      .read(planEditorControllerProvider.future)
      .then((_) => c.read(planEditorControllerProvider.notifier));

  PlanEditorState state(ProviderContainer c) =>
      c.read(planEditorControllerProvider).requireValue;

  test('no plan: an empty plan, nothing saved yet', () async {
    final c = container(repo);
    await editor(c);
    expect(state(c).plan.days, isEmpty);
    expect(_ok(await repo.loadPlan()), isNull);
  });

  test('build a plan from nothing: it is saved and becomes next', () async {
    final c = container(repo);
    final e = await editor(c);
    final dayId = await e.addDay(_chest);
    expect(dayId, startsWith('day-'));
    final benchId = await e.addExercise(dayId!, _bench);
    final flyId = await e.addExercise(dayId, _fly);
    expect(benchId, isNot(flyId));
    await e.setTargets(dayId, benchId!, sets: 4);
    await e.setTargets(dayId, benchId, weightStep: 1.25);

    final saved = _ok(await repo.loadPlan())!;
    expect(saved.days.single.name, _chest);
    final bench = saved.days.single.exercises.first;
    expect(bench.targetSets, 4);
    expect(bench.weightStep, 1.25);
    expect(state(c).nextDayId, dayId);

    final next = await c.read(nextWorkoutControllerProvider.future);
    expect(next!.day.name, _chest);
    expect(next.exercises, hasLength(2));
  });

  test('new exercise ids never reuse ids from the history', () async {
    await repo.savePlan(PlanTemplates.fiveDaySplit);
    final c = container(repo);
    final e = await editor(c);
    final taken = takenIds(PlanTemplates.fiveDaySplit, const []);
    final id = await e.addExercise('day-1', _bench);
    expect(taken, isNot(contains(id)));
    // Delete it and add again: a different id.
    await e.deleteExercise('day-1', id!);
    final again = await e.addExercise('day-1', _bench);
    expect(again, isNot(id));
  });

  test('renaming keeps the id, so the history stays', () async {
    await repo.savePlan(PlanTemplates.fiveDaySplit);
    final c = container(repo);
    final e = await editor(c);
    await e.renameExercise(
      'day-1',
      'flat_db_press',
      const LocalizedName(ar: 'بنش دمبل', en: 'DB Bench'),
    );
    final first = _ok(await repo.loadPlan())!.days.first.exercises.first;
    expect(first.id, 'flat_db_press');
    expect(first.name.en, 'DB Bench');
  });

  test('reordering days keeps the waiting workout', () async {
    await repo.savePlan(PlanTemplates.fiveDaySplit);
    await repo.saveSession(
      WorkoutSession(
        dayId: 'day-1',
        finishedAt: DateTime(2026, 11, 4, 19),
        sets: const [],
      ),
    );
    final c = container(repo);
    final e = await editor(c);
    expect(state(c).nextDayId, 'day-2');
    // Legs (day 3) between day 1 and day 2: the history alone would now
    // say legs.
    await e.moveDay(2, 1);
    expect(state(c).nextDayId, 'day-2');
    expect(
      _ok(await repo.loadChosenDay()),
      const ChosenDay('day-2', byEdit: true),
    );
    final next = await c.read(nextWorkoutControllerProvider.future);
    expect(next!.day.id, 'day-2');
  });

  test('deleting the waiting day: the day after it waits', () async {
    await repo.savePlan(PlanTemplates.fiveDaySplit);
    await repo.saveSession(
      WorkoutSession(
        dayId: 'day-1',
        finishedAt: DateTime(2026, 11, 4, 19),
        sets: const [],
      ),
    );
    final c = container(repo);
    final e = await editor(c);
    await e.deleteDay('day-2');
    final next = await c.read(nextWorkoutControllerProvider.future);
    expect(next!.day.id, 'day-3');
  });

  test('the day of the workout in progress is locked', () async {
    await repo.savePlan(PlanTemplates.fiveDaySplit);
    await repo.saveDraft(
      WorkoutDraft(dayId: 'day-1', startedAt: DateTime(2026, 11, 5, 17)),
    );
    final c = container(repo);
    final e = await editor(c);
    expect(state(c).lockedDayId, 'day-1');
    expect(await e.deleteDay('day-1'), PlanEditError.lockedDay);
    expect(
      await e.setTargets('day-1', 'flat_db_press', sets: 5),
      PlanEditError.lockedDay,
    );
    // Nothing changed on the phone.
    expect(_ok(await repo.loadPlan())!.days, hasLength(5));
    // Other days stay editable, and the locked one can move.
    expect(await e.deleteDay('day-5'), isNull);
    expect(await e.moveDay(0, 1), isNull);
    expect(_ok(await repo.loadPlan())!.days[1].id, 'day-1');
  });

  test('a failed save keeps the change on screen; retry saves it', () async {
    await repo.savePlan(PlanTemplates.fiveDaySplit);
    final flaky = _FailingSaves(repo);
    final c = container(flaky);
    final e = await editor(c);
    await e.renameDay('day-3', const LocalizedName(ar: 'أرجل', en: 'Leg day'));
    expect(state(c).saveFailure, isA<UnknownFailure>());
    expect(state(c).plan.days[2].name.en, 'Leg day');
    expect(_ok(await repo.loadPlan())!.days[2].name.en, 'Legs');

    await e.retrySave();
    expect(state(c).saveFailure, isNull);
    expect(_ok(await repo.loadPlan())!.days[2].name.en, 'Leg day');
  });

  test('a load failure is an error with retry', () async {
    final flaky = _FailingSaves(repo)..failLoad = true;
    final c = container(flaky);
    await expectLater(
      c.read(planEditorControllerProvider.future),
      throwsA(isA<ValidationFailure>()),
    );
    flaky.failLoad = false;
    await c.read(planEditorControllerProvider.notifier).retry();
    expect(c.read(planEditorControllerProvider).hasError, isFalse);
  });

  test('refused edits change nothing', () async {
    await repo.savePlan(
      const WorkoutPlan(
        days: [WorkoutDay(id: 'only', name: _chest, exercises: [])],
      ),
    );
    final c = container(repo);
    final e = await editor(c);
    expect(await e.deleteDay('only'), PlanEditError.lastDay);
    expect(
      await e.renameDay('only', const LocalizedName(ar: '', en: '')),
      PlanEditError.invalidName,
    );
    expect(await e.addExercise('nope', _bench), isNull);
    expect(state(c).plan.days.single.name, _chest);
  });

  test('hostile names are saved as text', () async {
    final c = container(repo);
    final e = await editor(c);
    const hostile = LocalizedName(
      ar: "'; DROP TABLE plan;--",
      en: r'<img src=x onerror=alert(1)> ${x}',
    );
    final id = await e.addDay(hostile);
    expect(id, isNotNull);
    expect(_ok(await repo.loadPlan())!.days.single.name, hostile);
  });
}
