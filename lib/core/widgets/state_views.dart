import 'package:flutter/material.dart';
import 'package:gym_tracker/core/adaptive/adaptive.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// Loading / empty / error views every screen uses, so the states look the
/// same across the app (CLAUDE.md → every screen has all states).
/// How big [LoadingView] is, by where it shows.
enum LoadingSize {
  /// In a row, a list item or next to text.
  inline,

  /// Inside a card or a section of a screen.
  card,

  /// The whole screen (the default).
  screen,
}

/// The looping Azm logo animation (figures only, no text), with one
/// "Loading" label for screen readers. Reduce Motion shows the static logo.
/// The background is transparent: it shows whatever is behind it.
class LoadingView extends StatelessWidget {
  const new({this.size = LoadingSize.screen, super.key});

  final LoadingSize size;

  @override
  Widget build(BuildContext context) {
    final side = switch (size) {
      LoadingSize.inline => AppDimens.loadingInline,
      LoadingSize.card => AppDimens.loadingCard,
      LoadingSize.screen => AppDimens.loadingScreen,
    };
    return Center(
      child: AzmLogoAnimation(
        size: side,
        loop: true,
        brightness: Theme.of(context).brightness,
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const new({
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
    super.key,
  });

  final String message;
  final IconData icon;

  /// The way out of the empty state, e.g. "Start with the 5-day plan".
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return _CenteredMessage(icon: icon, message: message, action: action);
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
