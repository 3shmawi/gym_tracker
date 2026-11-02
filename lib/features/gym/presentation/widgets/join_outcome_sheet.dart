import 'package:flutter/material.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// Which button of a [JoinOutcomeSheet] was tapped.
enum JoinOutcomeAction { primary, secondary }

/// Why joining did not work, as the member needs to hear it.
enum JoinOutcome {
  invalid,
  expired,
  used,
  conflict,
  throttled,

  /// No connection: the code was not used, trying again is fine.
  offline,

  /// Anything else that failed on the way (server, timeout).
  error;

  static JoinOutcome of(AppFailure failure) => switch (failure) {
    InviteFailure(:final problem) => switch (problem) {
      InviteProblem.invalid => JoinOutcome.invalid,
      InviteProblem.expired => JoinOutcome.expired,
      InviteProblem.used => JoinOutcome.used,
      InviteProblem.conflict => JoinOutcome.conflict,
      InviteProblem.throttled => JoinOutcome.throttled,
    },
    NetworkFailure() => JoinOutcome.offline,
    _ => JoinOutcome.error,
  };
}

/// Tells the member why a code did not work (design boards 2b and 3): three
/// different messages on purpose, so they know what to do next. None says
/// whether a code ever existed.
Future<JoinOutcomeAction?> showJoinOutcomeSheet(
  BuildContext context, {
  required JoinOutcome outcome,
}) => showAppSheet<JoinOutcomeAction>(
  context: context,
  builder: (_) => JoinOutcomeSheet(outcome: outcome),
);

class JoinOutcomeSheet extends StatelessWidget {
  const new({required this.outcome, super.key});

  final JoinOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final (icon, tone, title, body) = switch (outcome) {
      JoinOutcome.invalid => (
        Icons.warning_amber_rounded,
        AppOrbTone.error,
        l10n.joinInvalidTitle,
        l10n.joinInvalidBody,
      ),
      JoinOutcome.expired => (
        Icons.schedule,
        AppOrbTone.warning,
        l10n.joinExpiredTitle,
        l10n.joinExpiredBody,
      ),
      JoinOutcome.used => (
        Icons.smartphone,
        AppOrbTone.warning,
        l10n.joinUsedTitle,
        l10n.joinUsedBody,
      ),
      JoinOutcome.conflict => (
        Icons.person_off_outlined,
        AppOrbTone.warning,
        l10n.joinConflictTitle,
        l10n.joinConflictBody,
      ),
      JoinOutcome.throttled => (
        Icons.hourglass_top,
        AppOrbTone.warning,
        l10n.joinThrottledTitle,
        l10n.joinThrottledBody,
      ),
      JoinOutcome.offline => (
        Icons.wifi_off,
        AppOrbTone.warning,
        l10n.scanOfflineTitle,
        l10n.scanOfflineBody,
      ),
      JoinOutcome.error => (
        Icons.error_outline,
        AppOrbTone.error,
        l10n.joinErrorTitle,
        l10n.joinErrorBody,
      ),
    };
    // Only a wrong code is worth scanning again; the others can never work,
    // so they get an "OK" and a way to type another code.
    final (primary, secondary) = switch (outcome) {
      JoinOutcome.invalid => (l10n.joinScanAgain, l10n.joinTypeCode),
      JoinOutcome.throttled => (l10n.commonOk, null),
      JoinOutcome.offline ||
      JoinOutcome.error => (l10n.retry, l10n.joinTypeCode),
      _ => (l10n.commonOk, l10n.joinTypeOtherCode),
    };
    return SingleChildScrollView(
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
          Row(
            spacing: AppDimens.sm2,
            children: [
              AppOrb(icon: icon, tone: tone, size: 56),
              Expanded(
                child: Semantics(
                  header: true,
                  liveRegion: true,
                  child: Text(
                    title,
                    style: AppTextStyles.title.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Text(
            body,
            style: AppTextStyles.body.copyWith(
              color: palette.textSecondary,
              height: 1.6,
            ),
          ),
          AppPrimaryButton(
            key: const Key('join_outcome_primary'),
            label: primary,
            onPressed: () =>
                Navigator.of(context).pop(JoinOutcomeAction.primary),
          ),
          if (secondary != null)
            AppSecondaryButton(
              key: const Key('join_outcome_secondary'),
              label: secondary,
              onPressed: () =>
                  Navigator.of(context).pop(JoinOutcomeAction.secondary),
            ),
        ],
      ),
    );
  }
}
