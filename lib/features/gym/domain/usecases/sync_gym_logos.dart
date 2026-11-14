import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_logo_repository.dart';
import 'package:gym_tracker/features/gym/domain/usecases/gym_logo_check.dart';

/// Brings the phone's logos in line with the memberships
/// (docs/designs/gym_logo.md §5): downloads a logo that is new or replaced,
/// deletes one that was removed or whose gym is no longer an active
/// membership. One gym at a time; a failure leaves that gym as it was (its
/// letters, or the logo it had) until the next sync.
class SyncGymLogos {
  const new(this._remote, this._store, {this.onRefused});

  final GymLogoRepository _remote;
  final GymLogoStore _store;

  /// Told why downloaded bytes were refused (monitoring; no path or id).
  final void Function(GymLogoProblem problem)? onRefused;

  /// At most this many logos on the phone (about 5 MB).
  static const maxLogos = 10;

  /// The logos that should be on the phone for [memberships]: active ones
  /// with a logo, the first [maxLogos].
  static Map<String, GymLogoRef> wanted(List<Membership> memberships) {
    final out = <String, GymLogoRef>{};
    for (final m in memberships) {
      if (out.length == maxLogos) break;
      final logo = m.gym.logo;
      if (m.isActive && logo != null) out[m.gym.id] = logo;
    }
    return out;
  }

  /// Returns whether anything on the phone changed.
  Future<bool> call(List<Membership> memberships) async {
    final want = wanted(memberships);
    final have = await _store.load();
    var changed = false;

    for (final gymId in have.keys) {
      if (!want.containsKey(gymId)) {
        if (await _store.remove(gymId) is Success<void>) changed = true;
      }
    }

    for (final MapEntry(key: gymId, value: logo) in want.entries) {
      if (have[gymId]?.logo == logo) continue;
      final bytes = switch (await _remote.fetch(logo)) {
        Success(:final value) => value,
        Failed() => null,
      };
      if (bytes == null) continue;
      final problem = GymLogoCheck.inspect(bytes);
      if (problem != null) {
        onRefused?.call(problem);
        continue;
      }
      if (await _store.save(logo, bytes) is Success<StoredGymLogo>) {
        changed = true;
      }
    }
    return changed;
  }
}
