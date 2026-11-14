import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/feature_flags/feature_flags.dart';
import 'package:gym_tracker/core/monitoring/monitoring.dart';
import 'package:gym_tracker/features/gym/domain/repositories/gym_logo_repository.dart';
import 'package:gym_tracker/features/gym/domain/usecases/refresh_memberships.dart';
import 'package:gym_tracker/features/gym/domain/usecases/sync_gym_logos.dart';
import 'package:gym_tracker/features/gym/presentation/gym_providers.dart';

/// Override in tests.
final gymLogoRepositoryProvider = Provider<GymLogoRepository>(
  (ref) => Dependencies.gymLogoRepository,
);
final gymLogoStoreProvider = Provider<GymLogoStore>(
  (ref) => Dependencies.gymLogoStore,
);

/// Whether gyms' logos show (`Flags.gymLogos`). Starts from the answer kept
/// on the phone, so the tiles don't change a moment after opening, then asks
/// PostHog once and remembers what it said.
final gymLogosEnabledProvider = NotifierProvider<GymLogosFlag, bool>(
  GymLogosFlag.new,
);

class GymLogosFlag extends Notifier<bool> {
  @override
  bool build() {
    unawaited(_refresh());
    return Dependencies.flagCache.read(Flags.gymLogos) ?? false;
  }

  Future<void> _refresh() async {
    final bool enabled;
    try {
      enabled = await FeatureFlags.isEnabled(Flags.gymLogos);
    } on Object {
      return; // Keep the last known answer.
    }
    if (!ref.mounted) return;
    await Dependencies.flagCache.write(Flags.gymLogos, value: enabled);
    if (ref.mounted && state != enabled) state = enabled;
  }
}

/// The logos on the phone, by gym id. [GymLogoSync] reloads it when a
/// sync changed something.
final storedGymLogosProvider = FutureProvider<Map<String, StoredGymLogo>>(
  (ref) => ref.watch(gymLogoStoreProvider).load(),
);

/// The picture for each gym's tile that has one on the phone, by gym id.
/// A gym not in the map shows its letters: the flag off, no logo, or not
/// downloaded yet. A new logo is a new file name, so the image cache never
/// shows the previous one. Pages pass it to their views.
final gymLogoImagesProvider = Provider<Map<String, ImageProvider>>((ref) {
  if (!ref.watch(gymLogosEnabledProvider)) return const {};
  final stored = ref.watch(storedGymLogosProvider).value ?? const {};
  return {
    for (final MapEntry(:key, :value) in stored.entries)
      key: FileImage(File(value.filePath)),
  };
});

final gymLogoSyncProvider = Provider<GymLogoSync>(GymLogoSync.new);

/// Downloads the logos the memberships ask for. One sync at a time; a call
/// while one runs makes it run once more at the end, so the newest
/// memberships always win. Never throws.
class GymLogoSync {
  new(this._ref);

  final Ref _ref;
  Future<void>? _running;
  bool _again = false;

  Future<void> sync() {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    return _running = _loop().whenComplete(() => _running = null);
  }

  Future<void> _loop() async {
    do {
      _again = false;
      await _once();
    } while (_again && _ref.mounted);
  }

  Future<void> _once() async {
    if (!_ref.read(gymLogosEnabledProvider)) return;
    final memberships =
        _ref.read(gymControllerProvider).value?.memberships ?? const [];
    final changed = await SyncGymLogos(
      _ref.read(gymLogoRepositoryProvider),
      _ref.read(gymLogoStoreProvider),
      onRefused: (problem) => unawaited(
        // Why, never which gym or path.
        Monitoring.captureException(
          StateError('gym logo refused: ${problem.name}'),
          StackTrace.current,
        ),
      ),
    )(memberships);
    if (changed && _ref.mounted) _ref.invalidate(storedGymLogosProvider);
  }
}

/// The logo refs the memberships ask for, as one comparable value: a
/// change (a join, a new logo, a removed one) starts a sync.
String gymLogoWants(GymSnapshot? snapshot) {
  final memberships = snapshot?.memberships ?? const [];
  return [
    for (final MapEntry(:key, :value) in SyncGymLogos.wanted(
      memberships,
    ).entries)
      '$key:${value.path}:${value.version}',
  ].join(',');
}
