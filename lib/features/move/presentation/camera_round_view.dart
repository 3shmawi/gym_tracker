import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_colors.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/move/domain/entities/move_sound_mode.dart';
import 'package:gym_tracker/features/move/domain/entities/pose_frame.dart';
import 'package:gym_tracker/features/move/domain/entities/round.dart';
import 'package:gym_tracker/features/move/domain/games/game_rules.dart';
import 'package:gym_tracker/features/move/domain/games/stack_rules.dart';
import 'package:gym_tracker/features/move/presentation/camera_round_controller.dart';
import 'package:gym_tracker/features/move/presentation/game/stack_game_view.dart';
import 'package:gym_tracker/features/move/presentation/move_words.dart';
import 'package:gym_tracker/features/move/presentation/widgets/move_parts.dart';
import 'package:gym_tracker/features/move/presentation/widgets/move_results_view.dart';
import 'package:gym_tracker/features/move/presentation/widgets/pose_body_painter.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// `/move/<exercise>/play`: placement, 3-2-1, the round, pause and results
/// (design boards 3 and 5). While the round runs, the reps build the
/// exercise's game (Stack) in the middle of the screen.
class CameraRoundView extends StatelessWidget {
  const new({
    required this.state,
    required this.now,
    required this.exerciseName,
    required this.onClose,
    required this.onPause,
    required this.onResume,
    required this.onEnd,
    required this.onManual,
    required this.onSave,
    required this.onPlayAgain,
    required this.onDone,
    this.preview,
    this.onOpenSettings,
    this.onOpenProgress,
    this.onToggleSound,
    super.key,
  });

  final CameraRoundState state;
  final DateTime now;
  final String exerciseName;

  /// The live camera picture; null in tests and on the simulator (the
  /// body is then drawn from the joints).
  final Widget? preview;
  final VoidCallback onClose;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onEnd;
  final VoidCallback onManual;
  final VoidCallback onSave;
  final VoidCallback onPlayAgain;
  final VoidCallback onDone;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onOpenProgress;

  /// Mutes or unmutes the game; no button without it.
  final VoidCallback? onToggleSound;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
    if (state.stage == CameraStage.failed) {
      return _Trouble(
        trouble: state.trouble ?? CameraTrouble.noCamera,
        onManual: onManual,
        onOpenSettings: onOpenSettings,
      );
    }
    final live = state.stage == CameraStage.live;
    final running = live && round.phase == RoundPhase.running;
    return AppScaffold(
      title: running ? l10n.moveGameName : l10n.moveGetInPosition,
      leading: AppIconButton(
        key: const Key('move_round_close'),
        icon: Icons.close,
        tooltip: l10n.moveClose,
        onPressed: onClose,
      ),
      actions: [
        if (onToggleSound case final toggle?
            when state.stage != CameraStage.starting)
          AppIconButton(
            key: const Key('move_round_sound'),
            icon: switch (state.playing) {
              MoveSoundMode.voice => Icons.record_voice_over,
              MoveSoundMode.tones => Icons.volume_up,
              MoveSoundMode.off => Icons.volume_off,
            },
            tooltip: switch (state.playing) {
              MoveSoundMode.voice => l10n.moveSoundVoice,
              MoveSoundMode.tones => l10n.moveSoundTones,
              MoveSoundMode.off => l10n.moveSoundOff,
            },
            onPressed: toggle,
          ),
        if (running)
          AppIconButton(
            key: const Key('move_round_pause'),
            icon: Icons.pause,
            tooltip: l10n.movePause,
            onPressed: onPause,
          ),
      ],
      padBottom: false,
      body: switch (state.stage) {
        CameraStage.starting => const LoadingView(),
        CameraStage.placement => _Placement(state: state, preview: preview),
        CameraStage.live => switch (round.phase) {
          RoundPhase.countdown => _Camera(
            state: state,
            preview: preview,
            overlay: Countdown(seconds: round.countdownLeft(now) ?? 1),
          ),
          RoundPhase.paused => _Camera(
            state: state,
            preview: preview,
            dimmed: true,
            overlay: PausedSheet(
              reps: round.reps,
              clock: round.clock(now),
              bodyLost: round.pauseReason == PauseReason.bodyLost,
              onResume: onResume,
              onManual: onManual,
              onEnd: onEnd,
            ),
          ),
          _ => _Running(state: state, now: now, preview: preview),
        },
        CameraStage.failed => const SizedBox.shrink(),
      },
    );
  }
}

/// The camera picture, or the body drawn from the joints when there is
/// no picture (tests, the simulator).
class _Camera extends StatelessWidget {
  const new({
    required this.state,
    this.preview,
    this.overlay,
    this.dimmed = false,
  });

  final CameraRoundState state;
  final Widget? preview;
  final Widget? overlay;
  final bool dimmed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsetsDirectional.fromSTEB(
      AppDimens.md,
      AppDimens.sm,
      AppDimens.md,
      AppDimens.md,
    ),
    child: Semantics(
      label: context.l10n.moveCameraLabel,
      child: AppCameraBackdrop(
        dimmed: dimmed,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ?preview,
            ExcludeSemantics(
              child: _Pose(frame: state.frame, drawBody: preview == null),
            ),
            ?overlay,
          ],
        ),
      ),
    ),
  );
}

class _Pose extends StatelessWidget {
  const new({required this.frame, required this.drawBody});

  final PoseFrame? frame;
  final bool drawBody;

  @override
  Widget build(BuildContext context) => Center(
    child: AspectRatio(
      aspectRatio: (frame?.aspect ?? PoseFrame.defaultAspect).clamp(0.5, 1.5),
      child: CustomPaint(
        painter: PoseBodyPainter(
          frame: frame,
          outline: AppColors.cameraInkOutline,
          fill: AppColors.cameraInk,
          farFill: AppColors.cameraInkFar,
          dot: context.palette.brand,
          drawBody: drawBody,
        ),
      ),
    ),
  );
}

class _Placement extends StatelessWidget {
  const new({required this.state, this.preview});

  final CameraRoundState state;
  final Widget? preview;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final checks = state.checks;
    final hint = state.hint;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: _Camera(
            state: state,
            preview: preview,
            overlay: hint == null
                ? null
                : Align(
                    alignment: AlignmentDirectional.topCenter,
                    child: HintChip(text: hintLabel(l10n, hint)),
                  ),
          ),
        ),
        Flexible(
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: EdgeInsetsDirectional.fromSTEB(
                AppDimens.md,
                0,
                AppDimens.md,
                AppDimens.md,
              ),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: AppDimens.sm,
                  children: [
                    if (!checks.bodyFound)
                      Text(
                        l10n.movePlacementHow,
                        style: AppTextStyles.body.copyWith(
                          color: context.palette.textPrimary,
                        ),
                      ),
                    CheckRow(
                      done: checks.bodyFound && checks.inFrame,
                      text: l10n.moveCheckBody,
                    ),
                    CheckRow(
                      done: checks.viewFound,
                      text: l10n.movePlacementView,
                    ),
                    CheckRow(done: checks.light, text: l10n.moveCheckLight),
                    CheckRow(done: checks.plank, text: l10n.moveCheckPlank),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The round: the time, the game in the middle, the body and the reps
/// above it, the depth under it, and one notice or hint at a time.
class _Running extends StatelessWidget {
  const new({required this.state, required this.now, this.preview});

  final CameraRoundState state;
  final DateTime now;
  final Widget? preview;

  /// A half rep's or rushed rep's notice stays this long.
  static const noticeFor = Duration(milliseconds: 2500);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final round = state.round;
    final game = state.game;
    final notice = _notice(l10n, game?.last);
    final hint = state.hint;
    final chip = notice ?? (hint == null ? null : hintLabel(l10n, hint));
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppDimens.md,
        AppDimens.sm,
        AppDimens.md,
        AppDimens.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppDimens.sm,
        children: [
          RoundHud(clock: round.clock(now), reps: round.reps),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: AppDimens.scaled(72),
                height: AppDimens.scaled(96),
                child: ExcludeSemantics(
                  child: AppCameraBackdrop(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ?preview,
                        _Pose(frame: state.frame, drawBody: preview == null),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(child: RepsCounter(reps: round.reps)),
              SizedBox(width: AppDimens.scaled(72)),
            ],
          ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (game case final StackState stack)
                  StackGameView(state: stack),
                if (chip != null)
                  Align(
                    alignment: AlignmentDirectional.topCenter,
                    child: HintChip(
                      key: notice == null
                          ? null
                          : const Key('move_game_notice'),
                      text: chip,
                    ),
                  ),
              ],
            ),
          ),
          Center(
            child: SizedBox(
              width: AppDimens.scaled(200),
              child: Semantics(
                label: l10n.moveDepth,
                value: '${(state.rep.depth * 100).round()}%',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppDimens.radiusSm),
                  child: LinearProgressIndicator(
                    value: state.rep.depth,
                    minHeight: AppDimens.sm,
                    color: palette.brand,
                    backgroundColor: palette.fillSubtle,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// "Go lower" or "slow down" for a moment after a rep that didn't count.
  String? _notice(AppLocalizations l10n, GameMoment? last) {
    if (last == null) return null;
    final age = now.difference(last.at);
    if (age.isNegative || age > noticeFor) return null;
    return switch (last.kind) {
      GameMomentKind.halfRep => l10n.moveHalfRepNotice,
      GameMomentKind.tooFast => l10n.moveTooFastNotice,
      GameMomentKind.rep => null,
    };
  }
}

class _Trouble extends StatelessWidget {
  const new({
    required this.trouble,
    required this.onManual,
    this.onOpenSettings,
  });

  final CameraTrouble trouble;
  final VoidCallback onManual;
  final VoidCallback? onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final denied = trouble == CameraTrouble.denied;
    final (title, body) = switch (trouble) {
      CameraTrouble.denied => (l10n.moveDeniedTitle, l10n.moveDeniedBody),
      CameraTrouble.tooSlow => (
        l10n.moveUnsupportedTitle,
        l10n.moveTooSlowBody,
      ),
      CameraTrouble.noCamera || CameraTrouble.modelFailed => (
        l10n.moveUnsupportedTitle,
        l10n.moveNoCameraBody,
      ),
    };
    return AppScaffold(
      padBottom: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsets.all(AppDimens.md),
              children: [
                Center(
                  child: AppOrb(
                    icon: denied
                        ? Icons.no_photography_outlined
                        : Icons.phone_android,
                    tone: denied ? AppOrbTone.error : AppOrbTone.warning,
                  ),
                ),
                SizedBox(height: AppDimens.md),
                Semantics(
                  header: true,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headline.copyWith(
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                SizedBox(height: AppDimens.sm),
                Text(
                  body,
                  textAlign: TextAlign.center,
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
              padding: EdgeInsets.all(AppDimens.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppDimens.sm2,
                children: [
                  if (denied && onOpenSettings != null)
                    AppPrimaryButton(
                      key: const Key('move_trouble_settings'),
                      label: l10n.scanOpenSettings,
                      onPressed: onOpenSettings,
                    ),
                  if (denied && onOpenSettings != null)
                    AppSecondaryButton(
                      key: const Key('move_trouble_manual'),
                      label: l10n.moveCountByHand,
                      onPressed: onManual,
                    )
                  else
                    AppPrimaryButton(
                      key: const Key('move_trouble_manual'),
                      label: l10n.moveCountByHand,
                      onPressed: onManual,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
