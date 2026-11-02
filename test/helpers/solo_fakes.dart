import 'dart:math';

import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/solo_import.dart';
import 'package:gym_tracker/features/gym/domain/repositories/solo_import_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';

/// A fake `import_solo_data`: all-or-nothing per chunk, skips known
/// client ids, refuses chunks over 50 and duplicate ids, like the SQL.
/// `script` entries `before` / `after` drop the request or only the answer.
class FakeSoloServer implements SoloImportRepository {
  new({this.random, this.failRate = 0});

  final Random? random;
  final double failRate;
  final Map<String, ImportSession> stored = {};
  WorkoutPlan? plan;
  int calls = 0;
  int refusedChunks = 0;

  /// Fail the next calls: 'before' = never arrived, 'after' = stored but the
  /// answer was lost.
  final List<String> script = [];

  @override
  Future<Result<ImportAck>> importChunk(
    List<ImportSession> sessions, {
    WorkoutPlan? plan,
  }) async {
    calls++;
    var mode = script.isEmpty ? null : script.removeAt(0);
    if (mode == null && random != null && random!.nextDouble() < failRate) {
      mode = random!.nextBool() ? 'before' : 'after';
    }
    if (mode == 'before') return const Failed(NetworkFailure());
    if (sessions.length > maxChunk ||
        sessions.map((s) => s.clientId).toSet().length != sessions.length) {
      refusedChunks++;
      return const Failed(ValidationFailure());
    }
    var imported = 0;
    for (final s in sessions) {
      if (stored.putIfAbsent(s.clientId, () => s) == s) imported++;
    }
    var saved = false;
    if (plan != null && this.plan == null) {
      this.plan = plan;
      saved = true;
    }
    if (mode == 'after') return const Failed(TimeoutFailure());
    return Success(
      ImportAck(
        imported: imported,
        skipped: sessions.length - imported,
        planSaved: saved,
        soloTotal: stored.length,
      ),
    );
  }
}

/// A random history: some workouts the server would refuse, some repeated.
List<WorkoutSession> randomHistory(Random r, {int max = 200}) {
  final days = ['day-1', 'day-2', 'day-3', 'push_day'];
  final ids = ['bench', 'squat', 'pec_deck', 'row-2'];
  final out = <WorkoutSession>[];
  final n = r.nextInt(max + 1);
  for (var i = 0; i < n; i++) {
    final sets = [
      for (var k = 0; k < r.nextInt(12); k++)
        LoggedSet(
          exerciseId: ids[r.nextInt(ids.length)],
          weight: (r.nextInt(400)) / 2,
          reps: r.nextInt(30),
        ),
    ];
    out.add(
      WorkoutSession(
        dayId: days[r.nextInt(days.length)],
        finishedAt: DateTime.utc(2024)
            .add(Duration(minutes: r.nextInt(900000))),
        sets: sets,
      ),
    );
  }
  if (out.isNotEmpty && r.nextBool()) out.add(out[r.nextInt(out.length)]);
  if (r.nextInt(4) == 0) {
    out.add(
      WorkoutSession(
        dayId: 'day-1',
        finishedAt: DateTime.utc(2019, 5),
        sets: const [],
      ),
    );
  }
  return out;
}
