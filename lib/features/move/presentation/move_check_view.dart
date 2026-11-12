import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_event.dart';
import 'package:gym_tracker/features/move/domain/entities/rep_state.dart';
import 'package:gym_tracker/features/move/domain/repositories/pose_source.dart';
import 'package:gym_tracker/features/move/presentation/move_check_controller.dart';
import 'package:gym_tracker/features/move/presentation/widgets/pose_body_painter.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// The pose check (testers only): the body as the model sees it, the
/// model's speed and what the push-up detector decides, frame by frame.
/// Pure UI: [state] in, taps out.
class MoveCheckView extends StatelessWidget {
  const new({
    required this.state,
    required this.onStart,
    required this.onStop,
    required this.onReset,
    this.onOpenSettings,
    super.key,
  });

  final MoveCheckState state;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onReset;

  /// Shown when the camera was refused.
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final status = state.status;
    final running = status.state == PoseSourceState.running;
    final starting = status.state == PoseSourceState.starting;
    return AppScaffold(
      title: l10n.moveCheckTitle,
      body: ListView(
        padding: EdgeInsetsDirectional.fromSTEB(
          AppDimens.md,
          AppDimens.sm,
          AppDimens.md,
          AppDimens.lg,
        ),
        children: [
          Text(
            l10n.moveCheckIntro,
            style: AppTextStyles.body.copyWith(color: palette.textSecondary),
          ),
          SizedBox(height: AppDimens.md),
          AppCard(child: _Body(state: state)),
          SizedBox(height: AppDimens.sm2),
          AppCard(child: _Readout(state: state)),
          if (status.problem case final problem?) ...[
            SizedBox(height: AppDimens.sm2),
            _Problem(problem: problem, onOpenSettings: onOpenSettings),
          ],
          SizedBox(height: AppDimens.lg),
          if (starting)
            const LoadingView(size: LoadingSize.inline)
          else if (running)
            AppSecondaryButton(
              key: const Key('move_check_stop'),
              label: l10n.moveCheckStop,
              icon: Icons.stop_rounded,
              onPressed: onStop,
            )
          else
            AppPrimaryButton(
              key: const Key('move_check_start'),
              label: l10n.moveCheckStart,
              icon: Icons.photo_camera_outlined,
              onPressed: onStart,
            ),
          SizedBox(height: AppDimens.sm2),
          AppSecondaryButton(
            key: const Key('move_check_reset'),
            label: l10n.moveCheckReset,
            icon: Icons.restart_alt_rounded,
            onPressed: state.rep.reps == 0 && state.frames == 0
                ? null
                : onReset,
          ),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  const new({required this.state});

  final MoveCheckState state;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final frame = state.frame;
    final aspect = (frame?.aspect ?? 0.75).clamp(0.5, 1.5);
    return Semantics(
      image: true,
      label: context.l10n.moveCheckBodyLabel,
      excludeSemantics: true,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: AppDimens.scaled(280)),
          child: AspectRatio(
            aspectRatio: aspect,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.fillSubtle,
                borderRadius: BorderRadius.circular(AppDimens.radiusLg),
              ),
              child: frame == null
                  ? Icon(
                      Icons.accessibility_new_rounded,
                      size: AppDimens.scaled(64),
                      color: palette.textTertiary,
                    )
                  : CustomPaint(
                      painter: PoseBodyPainter(
                        frame: frame,
                        outline: palette.textPrimary,
                        fill: palette.surfaceSolid,
                        farFill: palette.fillSubtle,
                        dot: palette.brand,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Readout extends StatelessWidget {
  const new({required this.state});

  final MoveCheckState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final rep = state.rep;
    final fps = state.status.fps;
    final event = state.lastEvent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: AppDimens.sm,
      children: [
        _Row(
          label: l10n.moveCheckReps,
          value: Text(
            '${rep.reps}',
            key: const Key('move_check_reps'),
            style: AppTextStyles.numL.copyWith(color: palette.textPrimary),
          ),
        ),
        _Row(
          label: l10n.moveCheckSpeed,
          value: _text(
            context,
            fps == null
                ? l10n.moveCheckNotYet
                : l10n.moveCheckFps(fps.toStringAsFixed(1)),
          ),
        ),
        _Row(
          label: l10n.moveCheckView,
          value: _text(context, switch (rep.view) {
            PoseView.side => l10n.moveCheckViewSide,
            PoseView.front => l10n.moveCheckViewFront,
            null => l10n.moveCheckNotYet,
          }),
        ),
        _Row(
          label: l10n.moveCheckPosition,
          value: _text(context, phaseLabel(l10n, rep.phase)),
        ),
        _Row(
          label: l10n.moveCheckDepth,
          value: SizedBox(
            width: AppDimens.scaled(120),
            child: Semantics(
              value: '${(rep.depth * 100).round()}%',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppDimens.radiusSm),
                child: LinearProgressIndicator(
                  value: rep.depth,
                  minHeight: AppDimens.sm,
                  color: palette.brand,
                  backgroundColor: palette.fillSubtle,
                ),
              ),
            ),
          ),
        ),
        _Row(
          label: l10n.moveCheckLast,
          value: _text(
            context,
            event == null ? l10n.moveCheckNotYet : eventLabel(l10n, event),
          ),
        ),
      ],
    );
  }

  Widget _text(BuildContext context, String text) => Text(
    text,
    textAlign: TextAlign.end,
    style: AppTextStyles.body.copyWith(
      color: context.palette.textPrimary,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _Row extends StatelessWidget {
  const new({required this.label, required this.value});

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Row(
      spacing: AppDimens.sm2,
      children: [
        Text(
          label,
          style: AppTextStyles.body.copyWith(
            color: context.palette.textSecondary,
          ),
        ),
        Expanded(
          child: Align(alignment: AlignmentDirectional.centerEnd, child: value),
        ),
      ],
    ),
  );
}

class _Problem extends StatelessWidget {
  const new({required this.problem, this.onOpenSettings});

  final PoseProblem problem;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppDimens.sm2,
        children: [
          Text(switch (problem) {
            PoseProblem.denied => l10n.moveCheckDenied,
            PoseProblem.noCamera => l10n.moveCheckNoCamera,
            PoseProblem.modelFailed => l10n.moveCheckModelFailed,
          }, style: AppTextStyles.body.copyWith(color: palette.error)),
          if (problem == PoseProblem.denied && onOpenSettings != null)
            AppSecondaryButton(
              key: const Key('move_check_settings'),
              label: l10n.scanOpenSettings,
              icon: Icons.settings_outlined,
              onPressed: onOpenSettings,
            ),
        ],
      ),
    );
  }
}

/// Where the member is in a rep, in words.
String phaseLabel(AppLocalizations l10n, RepPhase phase) => switch (phase) {
  RepPhase.notVisible => l10n.moveCheckPhaseNotVisible,
  RepPhase.ready => l10n.moveCheckPhaseReady,
  RepPhase.goingDown => l10n.moveCheckPhaseGoingDown,
  RepPhase.bottom => l10n.moveCheckPhaseBottom,
  RepPhase.goingUp => l10n.moveCheckPhaseGoingUp,
};

/// What the detector noticed, in words. Hints are reused by Move games.
String eventLabel(AppLocalizations l10n, RepEvent event) => switch (event) {
  RepCounted() => l10n.moveCheckEventCounted,
  HalfRep() => l10n.moveCheckEventHalf,
  TooFast() => l10n.moveCheckEventTooFast,
  BodyLost() => l10n.moveCheckEventLost,
  BodyFound() => l10n.moveCheckEventFound,
  FormHint(:final kind) => switch (kind) {
    FormHintKind.straightBody => l10n.moveHintStraightBody,
    FormHintKind.moveBack => l10n.moveHintMoveBack,
    FormHintKind.moveCloser => l10n.moveHintMoveCloser,
    FormHintKind.moreLight => l10n.moveHintMoreLight,
  },
};
