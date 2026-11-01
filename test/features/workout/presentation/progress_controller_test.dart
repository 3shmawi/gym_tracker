import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/workout/data/datasources/plan_templates.dart';
import 'package:gym_tracker/features/workout/data/repositories/local_workout_repository.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';
import 'package:gym_tracker/features/workout/presentation/progress_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'progress_samples.dart';

void main() {
  late LocalWorkoutRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
  });

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [workoutRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('no plan: null (empty state)', () async {
    final c = container();
    expect(await c.read(progressOverviewProvider.future), isNull);
    expect(
      await c.read(exerciseHistoryProvider('flat_db_press').future),
      isNull,
    );
  });

  test('reads the plan and the saved history', () async {
    await repo.savePlan(PlanTemplates.fiveDaySplit);
    for (final s in progressSessions) {
      await repo.saveSession(s);
    }
    final c = container();
    final all = (await c.read(progressOverviewProvider.future))!;
    expect(all.first.gain, 2.5);
    final h = (await c.read(exerciseHistoryProvider('close_grip_row').future))!;
    expect(h.entries, hasLength(4));
  });

  test('corrupt stored history becomes an error, not a crash', () async {
    SharedPreferences.setMockInitialValues({
      LocalWorkoutRepository.planKey: '{"days":[]}',
      LocalWorkoutRepository.historyKey: '<script>',
    });
    repo = LocalWorkoutRepository(await SharedPreferences.getInstance());
    final c = container();
    await expectLater(
      c.read(progressOverviewProvider.future),
      throwsA(anything),
    );
  });
}
