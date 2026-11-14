import 'dart:async';

import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/backup/domain/entities/restore.dart';
import 'package:gym_tracker/features/backup/domain/repositories/backup_repositories.dart';
import 'package:gym_tracker/features/backup/domain/usecases/restore_sessions.dart';
import 'package:gym_tracker/features/workout/domain/repositories/restore_sink.dart';

/// The gym history restore's position, plus what a run needs to carry over
/// app sessions: the total added so far, when it last finished, and the
/// last real position (for the daily look for newer rows).
abstract interface class GymHistoryCursorStore implements RestoreCursorStore {
  int get added;
  Future<void> setAdded(int value);

  DateTime? get doneAt;

  /// Back to the last real position, so the next run asks only for rows
  /// after it.
  Future<void> reopen();

  Future<void> clear();
}

/// One run's outcome: `finished` when everything the server had was taken;
/// `added` counts the whole run, also across app sessions.
typedef GymHistoryRun = ({bool finished, int added, bool skipped});

/// After a recovery code, the person's workouts come back onto the phone
/// (docs/designs/gym_history_restore.md). Rows of their gyms, of ended gyms
/// that kept history readable, and solo rows they once backed up; only
/// their own (the remote asks by person).
class RestoreGymHistory {
  const new({
    required this.remote,
    required this.sink,
    required this.store,
    this.now = DateTime.now,
    this.pageSize = 200,
  });

  final BackupRemote remote;
  final RestoreSink sink;
  final GymHistoryCursorStore store;
  final DateTime Function() now;
  final int pageSize;

  /// After a finished run, look again for newer rows at most this often.
  static const recheckAfter = Duration(days: 1);

  /// Null when there is nothing to do now (finished, and checked lately).
  Future<Result<GymHistoryRun>?> call({void Function()? onPage}) async {
    if (store.read() == RestoreCursor.done) {
      final at = store.doneAt;
      if (at != null && now().difference(at) < recheckAfter) return null;
      await store.reopen();
    }
    final base = store.added;
    final result =
        await RestoreSessions(
          remote: remote,
          sink: sink,
          cursor: store,
          pageSize: pageSize,
        )(
          onProgress: (n) {
            onPage?.call();
            // Kept after every page: a run cut short still knows its total.
            unawaited(store.setAdded(base + n));
          },
        );
    switch (result) {
      case Failed(:final failure):
        return Failed(failure);
      case Success(:final value):
        final total = base + value.added;
        await store.setAdded(0);
        return Success((
          finished: true,
          added: total,
          skipped: value.skipped > 0,
        ));
    }
  }
}
