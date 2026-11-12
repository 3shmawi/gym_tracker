import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// "You already trained today" (Start another / Cancel), asked before a
/// second workout on the same day: from the home screen's Start and from the
/// floating workout pill. True: start it.
Future<bool> confirmTrainAgain(BuildContext context) async {
  final l10n = context.l10n;
  final go = await showAppSheet<bool>(
    context: context,
    builder: (sheet) => Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppDimens.md,
        0,
        AppDimens.md,
        AppDimens.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppDimens.sm2,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.todayAgainTitle,
              style: AppTextStyles.title.copyWith(
                color: sheet.palette.textPrimary,
              ),
            ),
          ),
          Text(
            l10n.todayAgainBody,
            style: AppTextStyles.body.copyWith(
              color: sheet.palette.textSecondary,
            ),
          ),
          AppPrimaryButton(
            key: const Key('start_again_confirm'),
            icon: Icons.play_arrow_rounded,
            label: l10n.todayAgainStart,
            onPressed: () => Navigator.of(sheet).pop(true),
          ),
          AppSecondaryButton(
            key: const Key('start_again_cancel'),
            label: l10n.workoutCancel,
            onPressed: () => Navigator.of(sheet).pop(false),
          ),
        ],
      ),
    ),
  );
  return go ?? false;
}
