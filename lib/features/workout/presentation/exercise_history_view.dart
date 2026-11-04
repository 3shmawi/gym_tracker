import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/workout/domain/entities/exercise_history.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/presentation/progress_format.dart';
import 'package:gym_tracker/features/workout/presentation/workout_format.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// One exercise: how far it moved since the first time, then every time it
/// was done, newest first, with the change from the time before (design
/// 3.3b). Data + callbacks only; `ExerciseHistoryPage` wires it.
class ExerciseHistoryView extends StatelessWidget {
  const new({
    required this.state,
    required this.onRetry,
    required this.now,
    super.key,
  });

  /// null value: the exercise isn't in the plan.
  final AsyncValue<ExerciseHistory?> state;
  final VoidCallback onRetry;
  final DateTime Function() now;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    return AppScaffold(
      title: state.value?.exercise.name.of(lang) ?? l10n.progressTitle,
      body: switch (state) {
        AsyncData(value: null) => EmptyView(
          icon: Icons.search_off,
          message: l10n.progressNotInPlan,
        ),
        AsyncData(value: final h?) when h.entries.isEmpty => EmptyView(
          icon: Icons.show_chart,
          message: l10n.progressNeverDone,
        ),
        AsyncData(value: final h?) => _History(history: h, now: now()),
        AsyncError(:final error) => ErrorView(
          failure: error is AppFailure ? error : UnknownFailure(error),
          onRetry: onRetry,
        ),
        _ => const LoadingView(),
      },
    );
  }
}

class _History extends StatelessWidget {
  const new({required this.history, required this.now});

  final ExerciseHistory history;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final lang = Localizations.localeOf(context).languageCode;
    final p = history.progress;
    final gain = ProgressFormat.change(l10n, p.gain!);
    final best = p.best!;
    final secondary = AppTextStyles.caption.copyWith(
      color: palette.textSecondary,
    );
    return ListView(
      padding: EdgeInsets.all(AppDimens.md),
      children: [
        Text(history.exercise.name.other(lang), style: secondary),
        if (history.days.isNotEmpty) ...[
          SizedBox(height: AppDimens.sm),
          // The workout it belongs to: "Chest & Back · Days 1, 4".
          Wrap(
            spacing: AppDimens.sm,
            runSpacing: AppDimens.xs,
            children: [
              for (final MapEntry(key: name, value: numbers) in _byName(
                history.days,
              ).entries)
                AppBadge(
                  label: _dayLabel(l10n, name.of(lang), numbers),
                  tone: AppTone.neutral,
                ),
            ],
          ),
        ],
        SizedBox(height: AppDimens.sm2),
        AppCard(
          key: const Key('progress_summary'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: AppDimens.sm,
            children: [
              Text(
                l10n.progressSince(
                  ProgressFormat.date(l10n, p.first!.date, now),
                ),
                style: secondary,
              ),
              Row(
                spacing: AppDimens.sm2,
                children: [
                  Expanded(
                    child: Text(
                      l10n.progressFromTo(
                        ProgressFormat.kg(
                          l10n,
                          p.first!.topWeight,
                          history.exercise.unit,
                        ),
                        ProgressFormat.kg(
                          l10n,
                          p.latest!.topWeight,
                          history.exercise.unit,
                        ),
                      ),
                      style: AppTextStyles.numM.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  AppBadge(label: gain.$1, tone: gain.$2),
                ],
              ),
              Text(
                [
                  l10n.progressBest(
                    WorkoutFormat.ltr(
                      WorkoutFormat.set(
                        best.weight,
                        best.reps,
                        history.exercise.unit,
                      ),
                    ),
                  ),
                  l10n.progressWorkouts(p.workouts),
                ].join(' · '),
                style: AppTextStyles.body.copyWith(color: palette.textPrimary),
              ),
            ],
          ),
        ),
        SizedBox(height: AppDimens.md),
        AppCard(
          key: const Key('history_list'),
          tall: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(l10n.progressHistory, style: secondary),
              ),
              for (final (i, e) in history.entries.indexed) ...[
                if (i > 0) Divider(height: 1, color: palette.fillSubtle),
                _EntryRow(entry: e, now: now, unit: history.exercise.unit),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// "Chest & Back · Days 1, 4". Arabic uses the Arabic comma, so the numbers
/// read in order right to left.
String _dayLabel(AppLocalizations l10n, String name, List<int> numbers) {
  final list = numbers.join(l10n.localeName == 'ar' ? '، ' : ', ');
  return '$name · ${l10n.progressPlanDays(numbers.length, list)}';
}

/// Day numbers per day name, in plan order: a plan that repeats a day
/// (Chest & Back on days 1 and 4) shows it once.
Map<LocalizedName, List<int>> _byName(List<PlanDayRef> days) {
  final byName = <LocalizedName, List<int>>{};
  for (final d in days) {
    (byName[d.name] ??= []).add(d.number);
  }
  return byName;
}

class _EntryRow extends StatelessWidget {
  const new({required this.entry, required this.now, required this.unit});

  final HistoryEntry entry;
  final DateTime now;
  final ExerciseUnit unit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final change = entry.change;
    final badge = change == null ? null : ProgressFormat.change(l10n, change);
    return MergeSemantics(
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
                    ProgressFormat.date(l10n, entry.date, now),
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary,
                    ),
                  ),
                  Text(
                    WorkoutFormat.ltr(
                      entry.sets
                          .map((s) => WorkoutFormat.set(s.weight, s.reps, unit))
                          .join(' · '),
                    ),
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (badge != null) AppBadge(label: badge.$1, tone: badge.$2),
          ],
        ),
      ),
    );
  }
}
