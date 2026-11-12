import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show NotifierProviderFamily;
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/presentation/move_providers.dart';
import 'package:gym_tracker/features/move/presentation/round_outcome.dart';
import 'package:meta/meta.dart';

@immutable
class ManualRoundState {
  const new({required this.round, this.outcome});

  final RoundState round;

  /// Set when the round has finished.
  final RoundOutcome? outcome;
}

final NotifierProviderFamily<
  ManualRoundController,
  ManualRoundState,
  MoveLaunch
>
manualRoundControllerProvider = NotifierProvider.autoDispose
    .family<ManualRoundController, ManualRoundState, MoveLaunch>(
      ManualRoundController.new,
    );

/// The manual counter (docs/designs/move_games.md §6): the same rounds,
/// results and saving, with no camera. The member taps after each rep.
class ManualRoundController extends Notifier<ManualRoundState>
    with RoundEnding {
  new(this.launch);

  final MoveLaunch launch;
  bool _finishing = false;

  DateTime get _now => ref.read(moveClockProvider)();

  @override
  ManualRoundState build() => ManualRoundState(
    round: RoundState(
      exercise: launch.exercise,
      kind: launch.kind,
      mode: RoundMode.manual,
    ),
  );

  void start() {
    if (state.round.phase != RoundPhase.ready) return;
    _set(state.round.startCountdown(_now));
    reportStarted(state.round);
  }

  void tap() => _set(state.round.addRep(_now));

  void undo() => _set(state.round.removeRep());

  /// Called a few times a second by the screen.
  void tick() => _set(state.round.tick(_now));

  void pause() => _set(state.round.pause(PauseReason.tap, _now));

  void resume() => _set(state.round.startCountdown(_now));

  void end() => _set(state.round.end(_now), ended: 'quit');

  void background() => _set(state.round.pause(PauseReason.background, _now));

  void _set(RoundState round, {String ended = 'completed'}) {
    if (identical(round, state.round)) return;
    state = ManualRoundState(round: round, outcome: state.outcome);
    if (round.phase == RoundPhase.finished && !_finishing) {
      _finishing = true;
      unawaited(_finish(round, ended));
    }
  }

  Future<void> _finish(RoundState round, String ended) async {
    final result = RoundResult.of(round);
    if (result == null) return;
    final outcome = await finishRound(result, ended: ended);
    if (ref.mounted) state = ManualRoundState(round: round, outcome: outcome);
  }

  Future<void> save() async {
    final outcome = state.outcome;
    if (outcome == null || outcome.save == SaveState.saving) return;
    state = ManualRoundState(
      round: state.round,
      outcome: outcome.copyWith(save: SaveState.saving),
    );
    final saved = await saveRound(outcome);
    if (!ref.mounted) return;
    state = ManualRoundState(
      round: state.round,
      outcome: outcome.copyWith(save: saved),
    );
  }
}
