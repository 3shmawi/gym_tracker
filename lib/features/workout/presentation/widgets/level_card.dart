import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/workout/domain/entities/level.dart';
import 'package:gym_tracker/features/workout/domain/usecases/get_level.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// The member's level on the home screen: the level figure, its name, the
/// weeks in a row and what the next level needs.
class LevelCard extends StatelessWidget {
  const new({required this.progress, super.key});

  final LevelProgress progress;

  static LevelFigure figureFor(Level level) => switch (level) {
    Level.beginner => LevelFigure.beginner,
    Level.intermediate => LevelFigure.intermediate,
    Level.pro => LevelFigure.pro,
  };

  static String nameOf(AppLocalizations l10n, Level level) => switch (level) {
    Level.beginner => l10n.levelBeginner,
    Level.intermediate => l10n.levelIntermediate,
    Level.pro => l10n.levelPro,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final next = progress.next;
    final weeksToNext = progress.weeksToNext;
    final secondary = AppTextStyles.caption.copyWith(
      color: palette.textSecondary,
    );
    return AppCard(
      key: const Key('level_card'),
      child: Row(
        spacing: AppDimens.md,
        children: [
          AzmLevelFigure(
            figure: figureFor(progress.level),
            width: AppDimens.levelFigure,
            brightness: Theme.of(context).brightness,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: AppDimens.xs,
              children: [
                Text(
                  '${l10n.levelTitle} · ${nameOf(l10n, progress.level)}',
                  style: AppTextStyles.label.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
                Text(
                  [
                    l10n.levelStreak(progress.streakWeeks),
                    if (next == null || weeksToNext == null)
                      l10n.levelTop
                    else
                      l10n.levelNext(weeksToNext, nameOf(l10n, next)),
                    if (progress.comeback) l10n.levelComeback,
                    if (progress.streakWeeks == 0)
                      l10n.levelWeekRule(const GetLevel().workoutsPerWeek),
                  ].join(' · '),
                  style: secondary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
