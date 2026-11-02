import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/analytics/analytics.dart';
import 'package:gym_tracker/core/di/dependencies.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/network/result.dart';
import 'package:gym_tracker/features/gym/domain/entities/solo_import.dart';
import 'package:gym_tracker/features/gym/domain/repositories/solo_import_repository.dart';
import 'package:gym_tracker/features/gym/domain/usecases/import_solo_data.dart';
import 'package:gym_tracker/features/gym/presentation/gym_providers.dart';
import 'package:gym_tracker/features/gym/presentation/join_controller.dart';
import 'package:gym_tracker/features/workout/presentation/next_workout_controller.dart';

/// Override in tests.
final soloImportRepositoryProvider = Provider<SoloImportRepository>(
  (ref) => Dependencies.soloImportRepository,
);
final soloImportStoreProvider = Provider<SoloImportStore>(
  (ref) => Dependencies.soloImportStore,
);

/// What the person chose, and how far a copy got.
final FutureProvider<SoloImportStatus> soloImportStatusProvider =
    FutureProvider<SoloImportStatus>(
      (ref) async => switch (await ref.watch(soloImportStoreProvider).load()) {
        Success(:final value) => value,
        Failed() => const SoloImportStatus(),
      },
    );

/// The phone's solo data, when it is worth asking about: someone is signed in,
/// there is something to copy, and they have not said "keep" or already copied.
/// Null otherwise.
final FutureProvider<SoloImportCandidates?> soloOfferProvider =
    FutureProvider<SoloImportCandidates?>((ref) async {
      if (!ref.watch(accountSessionProvider).isSignedIn) return null;
      final status = await ref.watch(soloImportStatusProvider.future);
      if (status.choice == SoloImportChoice.keep ||
          status.choice == SoloImportChoice.done) {
        return null;
      }
      final found = await FindSoloData(ref.watch(workoutRepositoryProvider))();
      return switch (found) {
        Success(:final value) when !value.isEmpty => value,
        _ => null,
      };
    });

sealed class SoloImportState {
  const new();
}

final class SoloIdle extends SoloImportState {
  const new();
}

final class SoloRunning extends SoloImportState {
  const new(this.done, this.total);

  final int done;
  final int total;
}

final class SoloFailed extends SoloImportState {
  const new(this.failure);

  final AppFailure failure;
}

final class SoloDone extends SoloImportState {
  const new();
}

final NotifierProvider<SoloImportController, SoloImportState>
soloImportControllerProvider = NotifierProvider(SoloImportController.new);

class SoloImportController extends Notifier<SoloImportState> {
  @override
  SoloImportState build() => const SoloIdle();

  SoloImportStore get _store => ref.read(soloImportStoreProvider);

  Future<void> _remember(SoloImportChoice choice) async {
    final current = switch (await _store.load()) {
      Success(:final value) => value,
      Failed() => const SoloImportStatus(),
    };
    await _store.save(current.copyWith(choice: choice));
    if (ref.mounted) ref.invalidate(soloImportStatusProvider);
  }

  /// "Keep my solo data": nothing leaves the phone, never asked again.
  Future<void> keep() => _remember(SoloImportChoice.keep);

  /// "Skip": not now.
  Future<void> skip() => _remember(SoloImportChoice.skip);

  /// "Add my solo history to my account". Also the way to carry on after a
  /// failure or an interruption: it always runs from the start, and what the
  /// server already has is skipped.
  Future<void> copy() async {
    if (state is SoloRunning) return;
    state = const SoloRunning(0, 0);
    unawaited(Analytics.capture('solo_import_started'));
    final result =
        await ImportSoloData(
          FindSoloData(ref.read(workoutRepositoryProvider)),
          ref.read(soloImportRepositoryProvider),
          _store,
          ref.read(workoutRepositoryProvider),
        )(
          onProgress: (done, total) {
            if (ref.mounted) state = SoloRunning(done, total);
          },
        );
    if (!ref.mounted) return;
    ref.invalidate(soloImportStatusProvider);
    switch (result) {
      case Success():
        unawaited(Analytics.capture('solo_import_done'));
        state = const SoloDone();
      case Failed(:final failure):
        unawaited(
          Analytics.capture('solo_import_failed', {
            'reason': JoinController.reasonOf(failure),
          }),
        );
        state = SoloFailed(failure);
    }
  }

  void reset() {
    if (state is! SoloRunning) state = const SoloIdle();
  }
}
