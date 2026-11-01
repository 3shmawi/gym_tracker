import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/workout/domain/entities/exercise_history.dart';
import 'package:gym_tracker/features/workout/presentation/progress_format.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// Every plan exercise with how far it moved since the first time: the
/// first and latest heaviest weight and the difference. Tap one for its
/// full history. Data + callbacks only; `ProgressPage` wires it.
class ProgressView extends StatelessWidget {
  const new({
    required this.state,
    required this.onRetry,
    required this.onOpen,
    super.key,
  });

  /// null value: no plan yet.
  final AsyncValue<List<ExerciseProgress>?> state;
  final VoidCallback onRetry;

  /// Opens the exercise's history (its id).
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppScaffold(
      title: l10n.progressTitle,
      body: switch (state) {
        AsyncData(value: null) => EmptyView(
          icon: Icons.show_chart,
          message: l10n.progressNoPlan,
        ),
        AsyncData(value: final all?) when all.every((p) => !p.started) =>
          EmptyView(icon: Icons.show_chart, message: l10n.progressEmpty),
        AsyncData(value: final all?) => ListView(
          padding: EdgeInsets.all(AppDimens.md),
          children: [
            AppCard(
              tall: true,
              child: Column(
                children: [
                  for (final (i, p) in all.indexed) ...[
                    if (i > 0)
                      Divider(height: 1, color: context.palette.fillSubtle),
                    _ProgressRow(
                      progress: p,
                      onTap: () => onOpen(p.exercise.id),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        AsyncError(:final error) => ErrorView(
          failure: error is AppFailure ? error : UnknownFailure(error),
          onRetry: onRetry,
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const new({required this.progress, required this.onTap});

  final ExerciseProgress progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final lang = Localizations.localeOf(context).languageCode;
    final p = progress;
    final gain = p.gain;
    final badge = gain == null ? null : ProgressFormat.change(l10n, gain);
    final detail = p.started
        ? [
            l10n.progressFromTo(
              ProgressFormat.kg(l10n, p.first!.topWeight),
              ProgressFormat.kg(l10n, p.latest!.topWeight),
            ),
            l10n.progressWorkouts(p.workouts),
          ].join(' · ')
        : l10n.progressNotDone;
    return MergeSemantics(
      child: Semantics(
        button: true,
        hint: l10n.progressOpenHint,
        child: InkWell(
          key: Key('progress_${p.exercise.id}'),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppDimens.minTouchTarget,
            ),
            child: Padding(
              padding: EdgeInsetsDirectional.symmetric(vertical: AppDimens.sm2),
              child: Row(
                spacing: AppDimens.sm2,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: 2,
                      children: [
                        Text(
                          p.exercise.name.of(lang),
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                            color: palette.textPrimary,
                          ),
                        ),
                        Text(
                          detail,
                          style: AppTextStyles.caption.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (badge != null) AppBadge(label: badge.$1, tone: badge.$2),
                  Icon(Icons.chevron_right, color: palette.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
