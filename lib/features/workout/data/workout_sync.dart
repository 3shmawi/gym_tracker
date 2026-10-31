import 'dart:async';

import 'package:gym_tracker/core/network/connectivity.dart';
import 'package:gym_tracker/features/workout/domain/repositories/workout_repository.dart';

/// Pushes queued workout writes whenever the device comes back online.
/// Started once from bootstrap; screens can also call
/// [WorkoutRepository.sync] directly (e.g. pull to refresh).
class WorkoutSync {
  new(this._repository, {Stream<bool>? onlineChanges})
    : _onlineChanges = onlineChanges ?? ConnectivityStatus.onlineChanges;

  final WorkoutRepository _repository;
  final Stream<bool> _onlineChanges;
  StreamSubscription<bool>? _subscription;

  void start() {
    _subscription ??= _onlineChanges.where((online) => online).listen((_) {
      unawaited(_repository.sync());
    });
  }

  Future<void> stop() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}
