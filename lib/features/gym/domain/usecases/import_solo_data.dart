import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/solo_import.dart';
import 'package:gym_tracker/features/gym/domain/repositories/solo_import_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';

/// How far a copy got, for the progress line.
typedef ImportProgress = void Function(int done, int total);

/// What there is to copy: the phone's workouts the server would accept, once
/// each, oldest first, and whether a plan exists.
class SoloImportCandidates {
  const new({
    required this.sessions,
    required this.skipped,
    required this.hasPlan,
  });

  final List<ImportSession> sessions;

  /// Workouts the server would refuse (a date before 2020 or in the future, an
  /// id it cannot store). They stay on the phone and are not counted.
  final int skipped;
  final bool hasPlan;

  bool get isEmpty => sessions.isEmpty && !hasPlan;
}

class FindSoloData {
  const new(this._workouts, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final WorkoutRepository _workouts;
  final DateTime Function() _now;

  Future<Result<SoloImportCandidates>> call() async {
    final history = await _workouts.loadHistory();
    final plan = await _workouts.loadPlan();
    final List<WorkoutSession> sessions;
    switch (history) {
      case Failed(:final failure):
        return Failed(failure);
      case Success(:final value):
        sessions = value;
    }
    final byId = <String, ImportSession>{};
    var skipped = 0;
    for (final s in sessions) {
      if (ImportSession.problemWith(s, now: _now()) != null) {
        skipped++;
        continue;
      }
      final item = ImportSession.fromSession(s);
      byId.putIfAbsent(item.clientId, () => item);
    }
    final ordered = byId.values.toList()
      ..sort((a, b) {
        final c = a.finishedAt.compareTo(b.finishedAt);
        return c != 0 ? c : a.clientId.compareTo(b.clientId);
      });
    return Success(
      SoloImportCandidates(
        sessions: ordered,
        skipped: skipped,
        hasPlan: switch (plan) {
          Success(:final value) => value != null,
          Failed() => false,
        },
      ),
    );
  }
}

/// Copies the phone's solo workouts and plan to the account in chunks of 50.
///
/// - **Idempotent:** the server skips a `client_id` it already has, so a chunk
///   sent twice (a dropped answer, a restart) changes nothing.
/// - **Resumable:** after any failure the status stays `copying` and the next
///   call simply runs again from the first workout; the chunks the server
///   already has are skipped, so no workout can be missed by a stale cursor.
///   `nextIndex` is only for the progress line.
/// - **Nothing is deleted:** the phone keeps its copy. It is marked `done`
///   only when the server's solo total covers every workout sent.
class ImportSoloData {
  const new(this._find, this._remote, this._store, this._workouts);

  final FindSoloData _find;
  final SoloImportRepository _remote;
  final SoloImportStore _store;
  final WorkoutRepository _workouts;

  Future<Result<SoloImportStatus>> call({ImportProgress? onProgress}) async {
    final stored = switch (await _store.load()) {
      Success(:final value) => value,
      Failed() => const SoloImportStatus(),
    };
    final found = await _find();
    if (found case Failed(:final failure)) return Failed(failure);
    final data = (found as Success<SoloImportCandidates>).value;
    final total = data.sessions.length;
    var status = stored.copyWith(choice: SoloImportChoice.copying);
    var index = 0;
    await _store.save(status.copyWith(nextIndex: 0));
    onProgress?.call(index, total);

    final plan = data.hasPlan
        ? switch (await _workouts.loadPlan()) {
            Success(:final value) => value,
            Failed() => null,
          }
        : null;
    var lastTotal = 0;
    var sentAny = false;
    // At least one call, so a plan with no workouts is still sent.
    while (index < total || !sentAny) {
      final end = (index + maxChunk).clamp(0, total);
      final chunk = data.sessions.sublist(index, end);
      final result = await _remote.importChunk(
        chunk,
        plan: sentAny ? null : plan,
      );
      switch (result) {
        case Failed(:final failure):
          return Failed(failure);
        case Success(:final value):
          lastTotal = value.soloTotal;
          sentAny = true;
          index = end;
          status = status.copyWith(nextIndex: index);
          await _store.save(status);
          onProgress?.call(index, total);
      }
      if (index >= total) break;
    }
    // The server must hold at least every workout we sent.
    if (lastTotal < total) {
      return const Failed(ValidationFailure());
    }
    status = status.copyWith(
      choice: SoloImportChoice.done,
      migratedAt: DateTime.now().toUtc(),
    );
    await _store.save(status);
    return Success(status);
  }
}
