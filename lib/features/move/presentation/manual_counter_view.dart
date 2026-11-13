import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/presentation/manual_round_controller.dart';
import 'package:gym_tracker/features/move/presentation/move_words.dart';
import 'package:gym_tracker/features/move/presentation/widgets/move_parts.dart';
import 'package:gym_tracker/features/move/presentation/widgets/move_results_view.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// `/move/<exercise>/count`: the same rounds with no camera (design board
/// 6). One big target: "tap after each rep"; −1 for a mistake. With a
/// screen reader, the target is one button that says the count.
class ManualCounterView extends StatelessWidget {
  const new({
    required this.state,
    required this.now,
    required this.exerciseName,
    required this.onStart,
    required this.onTap,
    required this.onUndo,
    required this.onPause,
    required this.onResume,
    required this.onEnd,
    required this.onSave,
    required this.onPlayAgain,
    required this.onDone,
    this.onOpenProgress,
    super.key,
  });

  final ManualRoundState state;
  final DateTime now;
  final String exerciseName;
  final VoidCallback onStart;
  final VoidCallback onTap;
  final VoidCallback onUndo;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onEnd;
  final VoidCallback onSave;
  final VoidCallback onPlayAgain;
  final VoidCallback onDone;
  final VoidCallback? onOpenProgress;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final round = state.round;
    final outcome = state.outcome;
    if (round.phase == RoundPhase.finished) {
      return AppScaffold(
        title: l10n.moveRoundDone,
        padBottom: false,
        body: outcome == null
            ? const LoadingView()
            : MoveResultsView(
                outcome: outcome,
                exerciseName: exerciseName,
                onSave: onSave,
                onPlayAgain: onPlayAgain,
                onDone: onDone,
                onOpenProgress: onOpenProgress,
              ),
      );
    }
    final running = round.phase == RoundPhase.running;
    return AppScaffold(
      title: l10n.moveCountByHand,
      actions: [
        if (running)
          AppIconButton(
            key: const Key('move_manual_pause'),
            icon: Icons.pause,
            tooltip: l10n.movePause,
            onPressed: onPause,
          ),
      ],
      padBottom: false,
      body: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            AppDimens.md,
            AppDimens.sm,
            AppDimens.md,
            AppDimens.md,
          ),
          child: switch (round.phase) {
            RoundPhase.ready => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      Text(
                        exerciseName,
                        style: AppTextStyles.headline.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                      SizedBox(height: AppDimens.sm),
                      Text(
                        l10n.moveManualIntro(roundLabel(l10n, round.kind)),
                        style: AppTextStyles.body.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                AppPrimaryButton(
                  key: const Key('move_manual_start'),
                  label: l10n.moveStart,
                  icon: Icons.play_arrow,
                  onPressed: onStart,
                ),
              ],
            ),
            RoundPhase.countdown => Countdown(
              seconds: round.countdownLeft(now) ?? 1,
            ),
            RoundPhase.paused => PausedSheet(
              reps: round.reps,
              clock: round.clock(now),
              onResume: onResume,
              onEnd: onEnd,
            ),
            RoundPhase.running || RoundPhase.finished => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppDimens.sm2,
              children: [
                RoundHud(clock: round.clock(now), reps: round.reps),
                RepsCounter(reps: round.reps),
                Expanded(
                  child: Semantics(
                    button: true,
                    label: l10n.moveTapLabel(round.reps),
                    excludeSemantics: true,
                    onTap: onTap,
                    child: Material(
                      color: palette.brandTint,
                      borderRadius: BorderRadius.circular(
                        AppDimens.radiusSheet,
                      ),
                      child: InkWell(
                        key: const Key('move_manual_tap'),
                        borderRadius: BorderRadius.circular(
                          AppDimens.radiusSheet,
                        ),
                        onTap: onTap,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            spacing: AppDimens.sm,
                            children: [
                              Icon(
                                Icons.touch_app_outlined,
                                size: AppDimens.scaled(56),
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              Text(
                                l10n.moveTapAfterEach,
                                textAlign: TextAlign.center,
                                style: AppTextStyles.title.copyWith(
                                  color: palette.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Center(
                  child: AppSecondaryButton(
                    key: const Key('move_manual_undo'),
                    label: l10n.moveUndoRep,
                    icon: Icons.remove,
                    onPressed: round.reps == 0 ? null : onUndo,
                  ),
                ),
              ],
            ),
          },
        ),
      ),
    );
  }
}
