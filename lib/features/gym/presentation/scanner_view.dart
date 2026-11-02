import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// What the scanner screen shows.
enum ScannerMode {
  /// The camera is on and reading.
  live,

  /// The member said no to the camera (or it is blocked).
  denied,

  /// No usable camera (none on the phone, or it failed to start).
  unavailable,

  /// A code was read and is being checked by the server.
  joining,

  /// The code could not be checked: no internet. The code was not used.
  offline,
}

/// "Scan your gym's code" (design boards 2a and 2b). Pure UI: the live camera
/// comes in as [camera], so tests and previews need no camera.
///
/// Every dead end offers "Type the code instead".
class ScannerView extends StatelessWidget {
  const new({
    required this.mode,
    required this.onClose,
    required this.onTypeCode,
    this.camera,
    this.refused = false,
    this.onOpenSettings,
    this.onRetry,
    super.key,
  });

  final ScannerMode mode;

  /// The live picture behind the viewfinder (null: the design's dark glow).
  final Widget? camera;

  /// The last code was refused: the viewfinder turns red.
  final bool refused;

  final VoidCallback onClose;
  final VoidCallback onTypeCode;
  final VoidCallback? onOpenSettings;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppScaffold(
      title: l10n.scanTitle,
      leading: AppIconButton(
        key: const Key('scanner_close'),
        icon: Icons.close,
        tooltip: l10n.commonClose,
        onPressed: onClose,
      ),
      padBottom: false,
      body: switch (mode) {
        ScannerMode.live => _Live(
          camera: camera,
          refused: refused,
          onTypeCode: onTypeCode,
        ),
        ScannerMode.joining => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: AppDimens.md,
            children: [
              const LoadingView(size: LoadingSize.card),
              Semantics(
                liveRegion: true,
                child: Text(
                  l10n.scanJoining,
                  style: AppTextStyles.title.copyWith(
                    color: context.palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        ScannerMode.denied => _Message(
          key: const Key('scanner_denied'),
          icon: Icons.no_photography_outlined,
          tone: AppOrbTone.muted,
          title: l10n.scanDeniedTitle,
          body: l10n.scanDeniedBody,
          primaryLabel: onOpenSettings == null ? null : l10n.scanOpenSettings,
          onPrimary: onOpenSettings,
          onTypeCode: onTypeCode,
        ),
        ScannerMode.unavailable => _Message(
          key: const Key('scanner_unavailable'),
          icon: Icons.no_photography_outlined,
          tone: AppOrbTone.muted,
          title: l10n.scanUnavailableTitle,
          body: l10n.scanUnavailableBody,
          primaryLabel: onRetry == null ? null : l10n.retry,
          onPrimary: onRetry,
          onTypeCode: onTypeCode,
        ),
        ScannerMode.offline => _Message(
          key: const Key('scanner_offline'),
          icon: Icons.wifi_off,
          tone: AppOrbTone.warning,
          title: l10n.scanOfflineTitle,
          body: l10n.scanOfflineBody,
          primaryLabel: onRetry == null ? null : l10n.retry,
          onPrimary: onRetry,
          onTypeCode: onTypeCode,
        ),
      },
    );
  }
}

class _Live extends StatelessWidget {
  const new({
    required this.camera,
    required this.refused,
    required this.onTypeCode,
  });

  final Widget? camera;
  final bool refused;
  final VoidCallback onTypeCode;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppDimens.md,
        AppDimens.xs,
        AppDimens.md,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppDimens.sm2,
        children: [
          Expanded(
            child: AppCameraBackdrop(
              dimmed: refused,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ?camera,
                  Center(child: AppViewfinder(refused: refused)),
                  PositionedDirectional(
                    start: AppDimens.sm2,
                    end: AppDimens.sm2,
                    bottom: AppDimens.sm2,
                    child: AppCard(
                      child: Text(
                        l10n.scanHint,
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsetsDirectional.only(bottom: AppDimens.md),
              child: AppSecondaryButton(
                key: const Key('scanner_type_code'),
                icon: Icons.keyboard_outlined,
                label: l10n.scanTypeInstead,
                onPressed: onTypeCode,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A state with an orb, a title and a line, and the way out at the bottom.
class _Message extends StatelessWidget {
  const new({
    required this.icon,
    required this.tone,
    required this.title,
    required this.body,
    required this.onTypeCode,
    this.primaryLabel,
    this.onPrimary,
    super.key,
  });

  final IconData icon;
  final AppOrbTone tone;
  final String title;
  final String body;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final VoidCallback onTypeCode;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: AppDimens.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                spacing: AppDimens.sm2 + 2,
                children: [
                  AppOrb(icon: icon, tone: tone),
                  Semantics(
                    header: true,
                    liveRegion: true,
                    child: Text(
                      title,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.headline.copyWith(
                        color: palette.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: AppDimens.scaled(300),
                    ),
                    child: Text(
                      body,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.body.copyWith(
                        color: palette.textSecondary,
                        fontSize: AppDimens.scaled(15),
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsetsDirectional.fromSTEB(
              AppDimens.md,
              0,
              AppDimens.md,
              AppDimens.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppDimens.sm2,
              children: [
                if (primaryLabel != null)
                  AppPrimaryButton(
                    key: const Key('scanner_primary'),
                    label: primaryLabel!,
                    onPressed: onPrimary,
                  ),
                AppSecondaryButton(
                  key: const Key('scanner_type_code'),
                  label: l10n.scanTypeInstead,
                  onPressed: onTypeCode,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
