import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/solo_import.dart';
import 'package:gym_tracker/features/gym/domain/repositories/session_outbox.dart';
import 'package:gym_tracker/features/gym/domain/repositories/solo_import_repository.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';

/// Queues a finished gym workout for upload. The id is the workout's content
/// hash (`ImportSession.clientId`), so queuing the same workout twice, or
/// uploading it twice, is one row on the server.
class QueueSession {
  const new(this._outbox);

  final SessionOutbox _outbox;

  Future<Result<void>> call(
    WorkoutSession session, {
    required String gymId,
    required String membershipId,
  }) => _outbox.add(
    OutboxEntry(
      clientId: ImportSession.fromSession(session).clientId,
      gymId: gymId,
      membershipId: membershipId,
      session: session,
    ),
  );
}

/// Uploads what is in the outbox, 50 at a time, oldest first. An entry leaves
/// the outbox only after the server confirmed it; a failure stops the run and
/// the next one carries on (retried by the caller with a back-off). Nothing
/// is ever changed or deleted on the phone's own history.
class UploadSessions {
  const new(this._outbox, this._uploader);

  final SessionOutbox _outbox;
  final SessionUploader _uploader;

  /// How many are left after this run (0 = all confirmed), or the failure.
  Future<Result<int>> call() async {
    final loaded = await _outbox.load();
    if (loaded case Failed(:final failure)) return Failed(failure);
    final all = [...(loaded as Success<List<OutboxEntry>>).value]
      ..sort((a, b) => a.session.finishedAt.compareTo(b.session.finishedAt));
    var left = all.length;
    for (var i = 0; i < all.length; i += maxChunk) {
      final chunk = all.sublist(i, (i + maxChunk).clamp(0, all.length));
      final sent = await _uploader.upload(chunk);
      if (sent case Failed(:final failure)) return Failed(failure);
      await _outbox.remove({for (final e in chunk) e.clientId});
      left -= chunk.length;
    }
    return Success(left);
  }
}
