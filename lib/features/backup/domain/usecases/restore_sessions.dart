import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/backup/domain/entities/restore.dart';
import 'package:gym_tracker/features/backup/domain/repositories/backup_repositories.dart';
import 'package:gym_tracker/features/workout/domain/repositories/restore_sink.dart';

/// Where a restore of workouts stands: the saved position (`finishedAt|id`),
/// [RestoreCursor.done] once everything was taken, or null (not started).
abstract interface class RestoreCursorStore {
  String? read();
  Future<void> write(String? value);
}

/// What one run brought onto the phone.
typedef RestoredSessions = ({int added, int skipped});

/// Brings the person's workouts down, 200 at a time, oldest first, saving
/// the position after every page (docs/designs/never_lose_history.md §4,
/// gym_history_restore.md §4). Used by the backup restore and by the gym
/// history restore: one page loop.
///
/// Never deletes or changes a workout on the phone: rows are added with
/// "insert or ignore" by their content key. A failure (the network, or the
/// phone's database refusing a page) keeps the position: the next call
/// carries on. A run that ends successfully has written `done`.
class RestoreSessions {
  const new({
    required this.remote,
    required this.sink,
    required this.cursor,
    this.pageSize = 200,
  });

  final BackupRemote remote;
  final RestoreSink sink;
  final RestoreCursorStore cursor;
  final int pageSize;

  /// [onProgress] hears the number added so far in this call.
  Future<Result<RestoredSessions>> call({
    void Function(int added)? onProgress,
  }) async {
    var added = 0;
    var skipped = 0;
    if (cursor.read() == RestoreCursor.done) {
      return const Success((added: 0, skipped: 0));
    }
    var position = RestoreCursor.parse(cursor.read());
    while (true) {
      final page = await remote.fetchSessions(after: position, limit: pageSize);
      final RestorePage value;
      switch (page) {
        case Failed(:final failure):
          return Failed(failure);
        case Success(value: final p):
          value = p;
      }
      // The phone's database can refuse a page (it holds at most 100 000
      // workouts): a failure like any other, never a throw past the caller.
      final stored = await guard(
        () => sink.addBackedUp(value.sessions),
        retries: 0,
      );
      switch (stored) {
        case Failed(:final failure):
          return Failed(failure);
        case Success(value: final n):
          added += n;
      }
      skipped += value.skipped;
      onProgress?.call(added);
      position = value.next;
      await cursor.write(position?.toString() ?? RestoreCursor.done);
      if (position == null) break;
    }
    return Success((added: added, skipped: skipped));
  }
}
