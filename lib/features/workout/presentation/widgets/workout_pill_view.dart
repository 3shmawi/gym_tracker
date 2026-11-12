import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/features/library/presentation/widgets/exercise_thumb.dart';
import 'package:gym_tracker/features/workout/presentation/workout_format.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// What the floating workout pill shows (design "Azm — exercise pictures,
/// workout pill", board 5).
@immutable
sealed class WorkoutPillData {
  const new();
}

/// No workout in progress: start the waiting day.
final class PillStart extends WorkoutPillData {
  const new({required this.dayNumber, required this.dayName});

  final int dayNumber;
  final String dayName;
}

/// A workout in progress: resume it. The ring shows the exercises done.
final class PillActive extends WorkoutPillData {
  const new({
    required this.exerciseId,
    required this.exerciseName,
    required this.done,
    required this.total,
  });

  final String exerciseId;
  final String exerciseName;
  final int done;
  final int total;
}

/// A rest is running: the ring and the clock count down.
final class PillResting extends WorkoutPillData {
  const new({
    required this.endsAt,
    required this.totalSeconds,
    required this.nextSet,
  });

  final DateTime endsAt;
  final int totalSeconds;
  final int nextSet;
}

/// The rest ran out away from the workout screen: go.
final class PillRestOver extends WorkoutPillData {
  const new({required this.nextSet, this.amount});

  final int nextSet;

  /// The next set's weight ("50 kg"); null for reps only.
  final String? amount;
}

/// The pill itself (196 × 64): a ring or picture, a title and a line.
/// One tap opens the workout (or starts it). Pure UI.
class WorkoutPillView extends StatelessWidget {
  const new({
    required this.data,
    required this.now,
    required this.onTap,
    super.key,
  });

  final WorkoutPillData data;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final over = data is PillRestOver;
    final foreground = over ? palette.onBrand : palette.textPrimary;
    final secondary = over ? palette.onBrand : palette.textSecondary;
    final (title, line, label) = switch (data) {
      PillStart(:final dayNumber, :final dayName) => (
        l10n.pillStart,
        l10n.pillDay(dayNumber, dayName),
        l10n.pillStartLabel(dayNumber, dayName),
      ),
      PillActive(:final exerciseName, :final done, :final total) => (
        l10n.pillResume,
        '$exerciseName · ${WorkoutFormat.ltr('$done/$total')}',
        l10n.pillResumeLabel(exerciseName, done, total),
      ),
      PillResting(:final nextSet) => (
        l10n.pillRest,
        l10n.pillNextSet(nextSet),
        l10n.pillRestLabel(_clock(_left)),
      ),
      PillRestOver(:final nextSet, :final amount) => (
        l10n.pillRestOver,
        [
          l10n.workoutSetChip(nextSet),
          if (amount != null) WorkoutFormat.ltr(amount),
        ].join(' · '),
        l10n.pillRestOverLabel(nextSet),
      ),
    };
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      // 196 wide, wider for long names or large text; never past the screen.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: AppDimens.pillWidth,
          maxWidth: math.max(
            AppDimens.pillWidth,
            math.min(
              AppDimens.scaled(300),
              MediaQuery.sizeOf(context).width - 2 * AppDimens.md,
            ),
          ),
        ),
        child: IntrinsicWidth(
          child: Material(
            key: const Key('workout_pill'),
            color: over ? palette.brand : palette.surfaceSolid,
            elevation: 3,
            shadowColor: Colors.black38,
            shape: StadiumBorder(side: BorderSide(color: palette.fillSubtle)),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: AppDimens.pillHeight),
                child: Padding(
                  padding: EdgeInsetsDirectional.symmetric(
                    horizontal: AppDimens.sm,
                    vertical: AppDimens.xs,
                  ),
                  child: Row(
                    spacing: AppDimens.sm2 - 2,
                    children: [
                      _lead(context),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: AppTextStyles.body.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w800,
                                height: 1.25,
                              ),
                            ),
                            Text(
                              line,
                              style: AppTextStyles.caption.copyWith(
                                color: secondary,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  int get _left => switch (data) {
    PillResting(:final endsAt) =>
      (endsAt.difference(now).inMilliseconds / 1000).ceil().clamp(0, 5999),
    _ => 0,
  };

  static String _clock(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  Widget _lead(BuildContext context) {
    final palette = context.palette;
    final ring = AppDimens.pillRing;
    switch (data) {
      case PillStart():
        return _Disc(
          color: palette.brand,
          child: Icon(
            Icons.play_arrow_rounded,
            size: ring * 0.5,
            color: palette.onBrand,
          ),
        );
      case PillRestOver():
        return _Disc(
          color: palette.onBrand,
          child: Icon(
            Icons.play_arrow_rounded,
            size: ring * 0.5,
            color: palette.brand,
          ),
        );
      case PillActive(:final exerciseId, :final done, :final total):
        return WorkoutPillRing(
          value: total == 0 ? 0 : done / total,
          child: ExerciseThumb(
            exerciseId: exerciseId,
            size: ring - AppDimens.scaled(14),
            background: Colors.transparent,
          ),
        );
      case PillResting(:final totalSeconds):
        return WorkoutPillRing(
          value: totalSeconds <= 0 ? 0 : _left / totalSeconds,
          // Grows with large text, up to what fits inside the ring.
          child: Text(
            WorkoutFormat.ltr(_clock(_left)),
            maxLines: 1,
            textScaler: MediaQuery.textScalerOf(context)
                .clamp(maxScaleFactor: 1.15),
            style: AppTextStyles.label.copyWith(
              color: palette.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: math.max(13, AppDimens.scaled(13)),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        );
    }
  }
}

/// The pill's ring: progress in brand green around [child].
class WorkoutPillRing extends StatelessWidget {
  const new({required this.value, required this.child, this.size, super.key});

  final double value;
  final Widget child;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final side = size ?? AppDimens.pillRing;
    return SizedBox.square(
      dimension: side,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.square(
            dimension: side,
            child: CircularProgressIndicator(
              value: value.clamp(0, 1).toDouble(),
              strokeWidth: AppDimens.scaled(4),
              color: context.palette.brand,
              backgroundColor: context.palette.fillSubtle,
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Disc extends StatelessWidget {
  const new({required this.color, required this.child});

  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: AppDimens.pillRing,
    height: AppDimens.pillRing,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    child: child,
  );
}

/// The pill tucked at the screen's edge (board 5.5): a small tab with the
/// ring. One tap brings the pill back.
class WorkoutPillTab extends StatelessWidget {
  const new({
    required this.atStart,
    required this.progress,
    required this.onTap,
    super.key,
  });

  /// At the start edge (left in English, right in Arabic).
  final bool atStart;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final radius = Radius.circular(AppDimens.pillHeight / 2);
    return Semantics(
      button: true,
      label: context.l10n.pillTabLabel,
      excludeSemantics: true,
      child: Material(
        key: const Key('workout_pill_tab'),
        color: palette.surfaceSolid,
        elevation: 3,
        shadowColor: Colors.black38,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: palette.fillSubtle),
          borderRadius: BorderRadiusDirectional.horizontal(
            start: atStart ? Radius.zero : radius,
            end: atStart ? radius : Radius.zero,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: AppDimens.minTouchTarget,
            height: AppDimens.pillHeight,
            child: Center(
              child: WorkoutPillRing(
                value: progress,
                size: AppDimens.scaled(30),
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
