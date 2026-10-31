import 'package:flutter/material.dart';
import 'package:gym_tracker/core/adaptive/adaptive.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// Loading / empty / error views every screen uses, so the states look the
/// same across the app (CLAUDE.md → every screen has all states).
class LoadingView extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator.adaptive());
}

class EmptyView extends StatelessWidget {
  const new({
    required this.message,
    this.icon = Icons.inbox_outlined,
    super.key,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _CenteredMessage(icon: icon, message: message);
  }
}

class ErrorView extends StatelessWidget {
  const new({required this.failure, this.onRetry, super.key});

  final AppFailure failure;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return _CenteredMessage(
      icon: failure is NetworkFailure
          ? Icons.wifi_off_outlined
          : Icons.error_outline,
      message: failure.message(context.l10n),
      action: onRetry == null
          ? null
          : AdaptiveButton(onPressed: onRetry, child: Text(context.l10n.retry)),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const new({required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppDimens.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: AppDimens.iconMd * 2, color: scheme.outline),
            SizedBox(height: AppDimens.md),
            Text(
              message,
              style: AppTextStyles.title,
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[SizedBox(height: AppDimens.lg), action!],
          ],
        ),
      ),
    );
  }
}

/// User-facing message for a failure, in the current language.
extension AppFailureMessage on AppFailure {
  String message(AppLocalizations l10n) => switch (this) {
    NetworkFailure() => l10n.errorNetwork,
    TimeoutFailure() => l10n.errorTimeout,
    UnauthorizedFailure() => l10n.errorUnauthorized,
    NotFoundFailure() => l10n.errorNotFound,
    ValidationFailure() => l10n.errorValidation,
    ServerFailure() || UnknownFailure() => l10n.errorUnknown,
  };
}
