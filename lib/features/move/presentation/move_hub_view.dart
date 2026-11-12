import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/features/library/presentation/widgets/exercise_illustration.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/presentation/move_words.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// `/move`: the exercises (push-ups for now), your best, the round length,
/// and the two ways to play (design board 1.3/1.4).
class MoveHubView extends StatelessWidget {
  const new({
    required this.exercise,
    required this.kind,
    required this.best,
    required this.onKind,
    required this.onCamera,
    required this.onManual,
    this.manualFirst = false,
    super.key,
  });

  final LibraryExercise exercise;
  final RoundKind kind;

  /// The best of [kind], or null before the first round.
  final int? best;
  final ValueChanged<RoundKind> onKind;
  final VoidCallback onCamera;
  final VoidCallback onManual;

  /// A screen reader is on: counting by hand comes first.
  final bool manualFirst;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final lang = Localizations.localeOf(context).languageCode;
    final camera = AppPrimaryButton(
      key: const Key('move_hub_camera'),
      label: l10n.movePlayCamera,
      icon: Icons.photo_camera_outlined,
      onPressed: onCamera,
    );
    final manual = AppSecondaryButton(
      key: const Key('move_hub_manual'),
      label: l10n.moveCountByHand,
      icon: Icons.touch_app_outlined,
      onPressed: onManual,
    );
    return AppScaffold(
      title: l10n.moveTitle,
      body: ListView(
        padding: EdgeInsetsDirectional.fromSTEB(
          AppDimens.md,
          AppDimens.sm,
          AppDimens.md,
          AppDimens.lg,
        ),
        children: [
          Text(
            l10n.moveHubIntro,
            style: AppTextStyles.body.copyWith(color: palette.textSecondary),
          ),
          SizedBox(height: AppDimens.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppDimens.sm2,
              children: [
                ExerciseIllustration(
                  exercise: exercise,
                  large: true,
                  height: AppDimens.scaled(140),
                ),
                Text(
                  exercise.defaults.name.of(lang),
                  style: AppTextStyles.title.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
                Text(
                  best == null
                      ? l10n.moveBestNone
                      : l10n.moveBest(best!, roundLabel(l10n, kind)),
                  key: const Key('move_hub_best'),
                  style: AppTextStyles.caption.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                Semantics(
                  header: true,
                  child: Text(
                    l10n.moveRound,
                    style: AppTextStyles.label.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ),
                Wrap(
                  spacing: AppDimens.sm,
                  runSpacing: AppDimens.sm,
                  children: [
                    for (final k in RoundKind.values)
                      AppChoiceChip(
                        key: Key('move_round_${k.id}'),
                        label: roundLabel(l10n, k),
                        selected: k == kind,
                        onTap: () => onKind(k),
                      ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: AppDimens.lg),
          if (manualFirst) manual else camera,
          SizedBox(height: AppDimens.sm2),
          if (manualFirst) camera else manual,
        ],
      ),
    );
  }
}
