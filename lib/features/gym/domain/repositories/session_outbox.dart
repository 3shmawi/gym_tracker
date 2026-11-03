import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_session.dart';
import 'package:meta/meta.dart';

/// A finished gym workout waiting to be uploaded.
@immutable
class OutboxEntry {
  const new({
    required this.clientId,
    required this.gymId,
    required this.membershipId,
    required this.session,
  });

  factory fromJson(Map<String, Object?> json) => OutboxEntry(
    clientId: json['client_id']! as String,
    gymId: json['gym_id']! as String,
    membershipId: json['membership_id']! as String,
    session: WorkoutSession.fromJson(json['session']! as Map<String, Object?>),
  );

  /// The workout's id: a hash of its content (`ImportSession`), so the same
  /// workout queued twice, or uploaded twice, is one row on the server.
  final String clientId;
  final String gymId;
  final String membershipId;
  final WorkoutSession session;

  Map<String, Object?> toJson() => {
    'client_id': clientId,
    'gym_id': gymId,
    'membership_id': membershipId,
    'session': session.toJson(),
  };
}

/// Finished gym workouts not yet confirmed by the server. Append-only: an
/// entry is added once (by `clientId`) and removed only when the server has
/// the workout.
abstract interface class SessionOutbox {
  Future<Result<List<OutboxEntry>>> load();

  /// Adds [entry] unless one with the same `clientId` is there.
  Future<Result<void>> add(OutboxEntry entry);

  /// Removes the entries with these ids (they are on the server).
  Future<Result<void>> remove(Set<String> clientIds);
}

/// Uploads workouts to the account.
abstract interface class SessionUploader {
  /// Stores up to 50 workouts; ones the server has already (same
  /// `clientId`) are not stored again. Success means every one of them is on
  /// the server now.
  Future<Result<void>> upload(List<OutboxEntry> entries);
}
