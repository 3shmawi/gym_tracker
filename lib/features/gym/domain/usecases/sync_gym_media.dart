import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_media.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_media_repository.dart';

/// Brings the phone's copy of a gym's media up to the server's: **the
/// server wins**. Never fails: offline, a failed request or a broken copy
/// leaves what the phone has (or nothing), and the screens fall back to the
/// bundled pictures.
class SyncGymMedia {
  const new(this._remote, this._store);

  final GymMediaRepository _remote;
  final GymMediaStore _store;

  /// The media to show now and whether it changed.
  Future<GymMediaSync> call(String gymId) async {
    final stored = await read(gymId);
    switch (await _remote.fetch(gymId)) {
      case Failed():
        return GymMediaSync(stored, changed: false);
      case Success(:final value):
        if (value == stored) return GymMediaSync(value, changed: false);
        if (value.isEmpty) {
          await _store.clear(gymId);
        } else {
          await _store.save(gymId, value);
        }
        return GymMediaSync(value, changed: true);
    }
  }

  /// The phone's copy only (no network): what an exercise screen shows first.
  Future<GymMedia> read(String gymId) async =>
      switch (await _store.load(gymId)) {
        Success(:final value) => value ?? GymMedia.empty,
        Failed() => GymMedia.empty,
      };
}

class GymMediaSync {
  const new(this.media, {required this.changed});

  final GymMedia media;
  final bool changed;
}
