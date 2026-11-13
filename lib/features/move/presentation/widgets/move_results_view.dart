import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/presentation/move_words.dart';
import 'package:gym_tracker/features/move/presentation/round_outcome.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// The end of a round (design boards 5.3, 5.4): the reps, the details, and
/// "Save to my training" (never automatic).
class MoveResultsView extends StatelessWidget {
  const new({
    required this.outcome,
    required this.exerciseName,
    required this.onSave,
    required this.onPlayAgain,
    required this.onDone,
    this.onOpenProgress,
    super.key,
  });

  final RoundOutcome outcome;
  final String exerciseName;
  final VoidCallback onSave;
  final VoidCallback onPlayAgain;
  final VoidCallback onDone;

  /// After saving: the exercise's history.
  final VoidCallback? onOpenProgress;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final r = outcome.result;
    final saved = outcome.save == SaveState.saved;
    final camera = r.mode == RoundMode.camera;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsetsDirectional.fromSTEB(
              AppDimens.md,
              AppDimens.sm,
              AppDimens.md,
              AppDimens.md,
            ),
            children: [
              AppCard(
                child: Column(
                  spacing: AppDimens.sm,
                  children: [
                    if (outcome.newBest)
                      AppBadge(
                        label: l10n.moveNewBest(roundLabel(l10n, r.kind)),
                        tone: AppTone.fresh,
                      ),
                    Semantics(
                      liveRegion: true,
                      label: l10n.moveRepsDone(r.reps, exerciseName),
                      excludeSemantics: true,
                      child: Column(
                        children: [
                          Text(
                            '${r.reps}',
                            key: const Key('move_results_reps'),
                            style: AppTextStyles.numHero.copyWith(
                              color: palette.textPrimary,
                            ),
                          ),
                          Text(
                            exerciseName,
                            style: AppTextStyles.title.copyWith(
                              color: palette.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: AppDimens.sm,
                      runSpacing: AppDimens.sm,
                      children: [
                        if (camera)
                          _Kpi(value: '${r.steady}', label: l10n.moveSteady),
                        if (camera)
                          _Kpi(
                            value: '${r.halfReps}',
                            label: l10n.moveHalfReps,
                          ),
                        _Kpi(
                          value: clockLabel(r.duration),
                          label: l10n.moveTime,
                        ),
                      ],
                    ),
                    if (!camera)
                      Text(
                        l10n.moveCountedByHand,
                        style: AppTextStyles.caption.copyWith(
                          color: palette.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: AppDimens.sm2),
              if (saved)
                AppBanner(
                  key: const Key('move_results_saved'),
                  icon: Icons.check_circle,
                  text: l10n.moveSaved(exerciseName, r.reps),
                )
              else if (outcome.save == SaveState.failed)
                AppBanner(
                  icon: Icons.error_outline,
                  text: l10n.moveSaveFailed,
                  tone: AppBannerTone.error,
                )
              else
                Text(
                  l10n.moveRestTip,
                  style: AppTextStyles.body.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              AppDimens.md,
              AppDimens.sm,
              AppDimens.md,
              AppDimens.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppDimens.sm2,
              children: [
                if (outcome.canSave && !saved)
                  AppPrimaryButton(
                    key: const Key('move_results_save'),
                    label: l10n.moveSave,
                    icon: Icons.bookmark_add_outlined,
                    onPressed: outcome.save == SaveState.saving ? null : onSave,
                  ),
                if (outcome.canSave && !saved)
                  Text(
                    l10n.moveSaveWhat(exerciseName, r.reps),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                if (saved && onOpenProgress != null)
                  AppPrimaryButton(
                    key: const Key('move_results_progress'),
                    label: l10n.moveSeeProgress,
                    onPressed: onOpenProgress,
                  ),
                AppSecondaryButton(
                  key: const Key('move_results_again'),
                  label: l10n.movePlayAgain,
                  onPressed: onPlayAgain,
                ),
                AppSecondaryButton(
                  key: const Key('move_results_done'),
                  label: saved || !outcome.canSave
                      ? l10n.moveDone
                      : l10n.moveNotNow,
                  onPressed: onDone,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Kpi extends StatelessWidget {
  const new({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return MergeSemantics(
      child: Container(
        constraints: BoxConstraints(minWidth: AppDimens.scaled(88)),
        padding: EdgeInsets.all(AppDimens.sm2),
        decoration: BoxDecoration(
          color: palette.fillSubtle,
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: AppTextStyles.numM.copyWith(color: palette.textPrimary),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(
                color: palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
