import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/features/library/presentation/widgets/exercise_illustration.dart';
import 'package:gym_tracker/l10n/l10n.dart';

enum MoveSetupStep {
  /// The form tip, before the first round of an exercise.
  tip,

  /// Why the camera, before it is asked for the first time.
  why,
}

/// `/move/<exercise>`: the form tip and the "why the camera" screen (design
/// boards 2.1, 2.2). Nothing here starts the camera: only a tap on
/// "Start camera" leads to the round.
class MoveSetupView extends StatelessWidget {
  const new({
    required this.step,
    required this.exercise,
    required this.onNext,
    required this.onManual,
    super.key,
  });

  final MoveSetupStep step;
  final LibraryExercise exercise;

  /// "Got it" on the tip, "Start camera" on the why screen.
  final VoidCallback onNext;
  final VoidCallback onManual;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final lang = Localizations.localeOf(context).languageCode;
    final body = switch (step) {
      MoveSetupStep.tip => <Widget>[
        ExerciseIllustration(
          exercise: exercise,
          large: true,
          height: AppDimens.scaled(150),
        ),
        Semantics(
          header: true,
          child: Text(
            l10n.moveTipTitle,
            style: AppTextStyles.headline.copyWith(color: palette.textPrimary),
          ),
        ),
        for (final (i, line) in [
          l10n.moveTip1,
          l10n.moveTip2,
          l10n.moveTip3,
        ].indexed)
          _Line(number: i + 1, text: line),
      ],
      MoveSetupStep.why => <Widget>[
        const Center(child: AppOrb(icon: Icons.photo_camera_outlined)),
        Semantics(
          header: true,
          child: Text(
            l10n.moveWhyTitle,
            textAlign: TextAlign.center,
            style: AppTextStyles.headline.copyWith(color: palette.textPrimary),
          ),
        ),
        Text(
          l10n.moveWhyBody,
          textAlign: TextAlign.center,
          style: AppTextStyles.body.copyWith(color: palette.textSecondary),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppDimens.sm2,
            children: [
              _Check(l10n.moveWhyNoRecording),
              _Check(l10n.moveWhyStaysOnPhone),
              _Check(l10n.moveWhyClosesAfter),
            ],
          ),
        ),
      ],
    };
    return AppScaffold(
      title: exercise.defaults.name.of(lang),
      padBottom: false,
      body: Column(
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
                for (final (i, w) in body.indexed) ...[
                  if (i > 0) SizedBox(height: AppDimens.sm2),
                  w,
                ],
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
                  AppPrimaryButton(
                    key: const Key('move_setup_next'),
                    label: step == MoveSetupStep.tip
                        ? l10n.moveTipGotIt
                        : l10n.moveStartCamera,
                    icon: step == MoveSetupStep.why
                        ? Icons.photo_camera_outlined
                        : null,
                    onPressed: onNext,
                  ),
                  if (step == MoveSetupStep.why)
                    AppSecondaryButton(
                      key: const Key('move_setup_manual'),
                      label: l10n.moveCountByHandInstead,
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

class _Line extends StatelessWidget {
  const new({required this.number, required this.text});

  final int number;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: AppDimens.sm2,
      children: [
        ExcludeSemantics(
          child: Container(
            constraints: BoxConstraints(
              minWidth: AppDimens.scaled(28),
              minHeight: AppDimens.scaled(28),
            ),
            padding: EdgeInsets.all(AppDimens.xs),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.fillSubtle,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: AppTextStyles.label.copyWith(color: palette.textSecondary),
            ),
          ),
        ),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.body.copyWith(color: palette.textPrimary),
          ),
        ),
      ],
    );
  }
}

class _Check extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      spacing: AppDimens.sm2,
      children: [
        Icon(Icons.check_circle, color: palette.brand),
        Expanded(
          child: Text(
            text,
            style: AppTextStyles.body.copyWith(color: palette.textPrimary),
          ),
        ),
      ],
    );
  }
}
