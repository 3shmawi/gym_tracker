import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/backup/domain/usecases/email_rules.dart';
import 'package:gym_tracker/features/backup/presentation/backup_sign_in_controller.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// "Back up my training": email, then the 6-digit code, then done (design
/// board "Backup and restore": offer, email, code, done). Pure UI: the
/// controller decides, this draws and reports taps.
class BackupSignInView extends StatefulWidget {
  const new({
    required this.step,
    required this.email,
    required this.onSubmitEmail,
    required this.onSubmitCode,
    required this.onResend,
    required this.onChangeEmail,
    required this.onUseExisting,
    required this.onDone,
    this.busy = false,
    this.problem,
    this.resendIn = 0,
    super.key,
  });

  final BackupStep step;

  /// The address a code was sent to (shown on the code step).
  final String email;
  final bool busy;
  final BackupProblem? problem;

  /// Seconds until "send a new code" works again (0 = now).
  final int resendIn;
  final ValueChanged<String> onSubmitEmail;
  final ValueChanged<String> onSubmitCode;
  final VoidCallback onResend;
  final VoidCallback onChangeEmail;
  final VoidCallback onUseExisting;
  final VoidCallback onDone;

  @override
  State<BackupSignInView> createState() => _BackupSignInViewState();
}

class _BackupSignInViewState extends State<BackupSignInView> {
  late final TextEditingController _email = TextEditingController(
    text: widget.email,
  );
  final _code = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  String? _problemText(AppLocalizations l10n) => switch (widget.problem) {
    null => null,
    BackupProblem.invalidEmail => l10n.backupEmailInvalid,
    BackupProblem.invalidCode ||
    BackupProblem.wrongOrExpired => l10n.backupCodeWrong,
    BackupProblem.tooMany => l10n.backupTooMany,
    BackupProblem.emailTaken => l10n.backupEmailTaken,
    BackupProblem.offline => l10n.errorNetwork,
    BackupProblem.server => l10n.errorUnknown,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final done = widget.step == BackupStep.done;
    final problem = _problemText(l10n);
    return AppScaffold(
      title: l10n.backupTitle,
      body: ListView(
        padding: EdgeInsetsDirectional.fromSTEB(
          AppDimens.md,
          AppDimens.xs,
          AppDimens.md,
          AppDimens.xl,
        ),
        children: [
          Center(
            child: AppOrb(
              icon: done
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_upload_outlined,
              size: 80,
            ),
          ),
          SizedBox(height: AppDimens.sm2),
          Semantics(
            header: true,
            child: Text(
              switch (widget.step) {
                BackupStep.email => l10n.backupHeadline,
                BackupStep.code => l10n.backupCodeTitle,
                BackupStep.done => l10n.backupDoneTitle,
              },
              textAlign: TextAlign.center,
              style: AppTextStyles.headline.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: AppDimens.scaled(22),
              ),
            ),
          ),
          SizedBox(height: AppDimens.sm),
          Text(
            switch (widget.step) {
              BackupStep.email => l10n.backupOfferBody,
              BackupStep.code => l10n.backupCodeSent(widget.email),
              BackupStep.done => l10n.backupDoneBody,
            },
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(
              color: palette.textSecondary,
              height: 1.5,
            ),
          ),
          SizedBox(height: AppDimens.md),
          ...switch (widget.step) {
            BackupStep.email => _emailStep(l10n, problem),
            BackupStep.code => _codeStep(l10n, problem),
            BackupStep.done => [
              AppPrimaryButton(
                key: const Key('backup_done'),
                label: l10n.backupDone,
                onPressed: widget.onDone,
              ),
            ],
          },
        ],
      ),
    );
  }

  List<Widget> _emailStep(AppLocalizations l10n, String? problem) {
    final fieldError = widget.problem == BackupProblem.invalidEmail
        ? problem
        : null;
    final note = fieldError == null ? problem : null;
    return [
      AppTextField(
        key: const Key('backup_email'),
        label: l10n.backupEmailLabel,
        controller: _email,
        helper: l10n.backupEmailHelper,
        error: fieldError,
        maxLength: EmailRules.maxLength,
        textDirection: TextDirection.ltr,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        textInputAction: TextInputAction.done,
        onSubmitted: widget.busy ? null : widget.onSubmitEmail,
      ),
      if (note != null) ...[
        SizedBox(height: AppDimens.sm),
        AppBanner(
          key: const Key('backup_problem'),
          icon: Icons.info_outline,
          text: note,
          tone: widget.problem == BackupProblem.emailTaken
              ? AppBannerTone.warning
              : AppBannerTone.error,
        ),
      ],
      if (widget.problem == BackupProblem.emailTaken) ...[
        SizedBox(height: AppDimens.sm),
        Text(
          l10n.backupUseExistingWarning,
          style: AppTextStyles.caption.copyWith(
            color: context.palette.textSecondary,
            height: 1.6,
          ),
        ),
        SizedBox(height: AppDimens.sm),
        AppSecondaryButton(
          key: const Key('backup_use_existing'),
          label: l10n.backupUseExisting,
          onPressed: widget.busy ? null : widget.onUseExisting,
        ),
      ],
      SizedBox(height: AppDimens.md),
      AppPrimaryButton(
        key: const Key('backup_send_code'),
        label: l10n.backupSendCode,
        onPressed: widget.busy ? null : () => widget.onSubmitEmail(_email.text),
      ),
    ];
  }

  List<Widget> _codeStep(AppLocalizations l10n, String? problem) {
    final wrong =
        widget.problem == BackupProblem.wrongOrExpired ||
        widget.problem == BackupProblem.invalidCode;
    return [
      AppCodeField(
        key: const Key('backup_code'),
        label: l10n.backupCodeLabel,
        controller: _code,
        length: 6,
        clean: EmailRules.code,
        hasError: wrong,
        autofocus: true,
        keyboardType: TextInputType.number,
        autofillHints: const [AutofillHints.oneTimeCode],
        onChanged: (_) => setState(() {}),
        onSubmitted: widget.busy ? null : widget.onSubmitCode,
      ),
      if (problem != null) ...[
        SizedBox(height: AppDimens.sm),
        AppBanner(
          key: const Key('backup_problem'),
          icon: Icons.info_outline,
          text: problem,
          tone: AppBannerTone.error,
        ),
      ],
      SizedBox(height: AppDimens.md),
      AppPrimaryButton(
        key: const Key('backup_verify'),
        label: l10n.backupVerify,
        onPressed: widget.busy || !EmailRules.isCode(_code.text)
            ? null
            : () => widget.onSubmitCode(_code.text),
      ),
      SizedBox(height: AppDimens.sm),
      AppSecondaryButton(
        key: const Key('backup_resend'),
        label: widget.resendIn > 0
            ? l10n.backupResendIn(widget.resendIn)
            : l10n.backupResend,
        onPressed: widget.busy || widget.resendIn > 0 ? null : widget.onResend,
      ),
      SizedBox(height: AppDimens.sm),
      AppSecondaryButton(
        key: const Key('backup_change_email'),
        label: l10n.backupChangeEmail,
        onPressed: widget.busy ? null : widget.onChangeEmail,
      ),
    ];
  }
}
