import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/move/presentation/move_words.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// 3, 2, 1 (a number change, never a zoom: Reduce Motion is respected).
class Countdown extends StatelessWidget {
  const new({required this.seconds, super.key});

  final int seconds;

  @override
  Widget build(BuildContext context) => Center(
    child: Semantics(
      liveRegion: true,
      label: '$seconds',
      child: AppCard(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: AppDimens.md),
          child: Text(
            '$seconds',
            key: const Key('move_countdown'),
            style: AppTextStyles.numHero.copyWith(
              color: context.palette.textPrimary,
            ),
          ),
        ),
      ),
    ),
  );
}

/// The time and the reps, at the top of a round.
class RoundHud extends StatelessWidget {
  const new({required this.clock, required this.reps, super.key});

  final Duration clock;
  final int reps;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      children: [
        Semantics(
          label: context.l10n.moveTime,
          value: clockLabel(clock),
          excludeSemantics: true,
          child: Text(
            clockLabel(clock),
            key: const Key('move_clock'),
            textDirection: TextDirection.ltr,
            style: AppTextStyles.numL.copyWith(color: palette.textPrimary),
          ),
        ),
      ],
    );
  }
}

/// The big rep count, announced to screen readers.
class RepsCounter extends StatelessWidget {
  const new({required this.reps, super.key});

  final int reps;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: context.l10n.moveRepsSoFar(reps),
    excludeSemantics: true,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$reps',
          key: const Key('move_reps'),
          style: AppTextStyles.numHero.copyWith(
            color: context.palette.textPrimary,
          ),
        ),
        Text(
          context.l10n.moveRepsUnit,
          style: AppTextStyles.label.copyWith(
            color: context.palette.textSecondary,
          ),
        ),
      ],
    ),
  );
}

/// One hint at a time, spoken by the screen reader.
class HintChip extends StatelessWidget {
  const new({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(AppDimens.sm),
    child: Semantics(
      liveRegion: true,
      child: AppBanner(
        icon: Icons.info_outline,
        text: text,
        tone: AppBannerTone.warning,
      ),
    ),
  );
}

/// A placement check: green when done.
class CheckRow extends StatelessWidget {
  const new({required this.done, required this.text, super.key});

  final bool done;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return MergeSemantics(
      child: Row(
        spacing: AppDimens.sm2,
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: done ? palette.brand : palette.textTertiary,
            semanticLabel: done
                ? context.l10n.moveCheckDone
                : context.l10n.moveCheckWaiting,
          ),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.body.copyWith(
                color: done ? palette.textPrimary : palette.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Paused (by a tap, the body leaving the picture, or the app leaving the
/// foreground): the reps are kept, and the way on is one tap.
class PausedSheet extends StatelessWidget {
  const new({
    required this.reps,
    required this.clock,
    required this.onResume,
    required this.onEnd,
    this.onManual,
    this.bodyLost = false,
    super.key,
  });

  final int reps;
  final Duration clock;
  final bool bodyLost;
  final VoidCallback onResume;
  final VoidCallback onEnd;

  /// "Switch to counting by hand" (camera rounds only).
  final VoidCallback? onManual;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    return Align(
      alignment: AlignmentDirectional.bottomCenter,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(AppDimens.sm2),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppDimens.sm2,
            children: [
              Semantics(
                header: true,
                liveRegion: true,
                child: Text(
                  bodyLost ? l10n.moveComeBack : l10n.movePaused,
                  style: AppTextStyles.title.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
              Text(
                l10n.movePausedBody(reps, clockLabel(clock)),
                style: AppTextStyles.body.copyWith(
                  color: palette.textSecondary,
                ),
              ),
              if (!bodyLost)
                AppPrimaryButton(
                  key: const Key('move_resume'),
                  label: l10n.moveResume,
                  icon: Icons.play_arrow,
                  onPressed: onResume,
                ),
              if (onManual != null)
                AppSecondaryButton(
                  key: const Key('move_switch_manual'),
                  label: l10n.moveSwitchToManual,
                  onPressed: onManual,
                ),
              AppSecondaryButton(
                key: const Key('move_end'),
                label: l10n.moveEndRound,
                onPressed: onEnd,
              ),
              Text(
                l10n.moveStopIfHurts,
                textAlign: TextAlign.center,
                style: AppTextStyles.caption.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
