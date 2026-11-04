import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// "Before you start": once, before the app's features (YouTube API
/// Services Developer Policies III.A: users agree to the privacy policy
/// first; the terms say YouTube's Terms of Service apply). Pure UI.
class ConsentView extends StatelessWidget {
  const new({
    required this.onAgree,
    required this.onOpenPrivacy,
    required this.onOpenTerms,
    required this.onOpenYouTubeTerms,
    required this.onOpenGooglePrivacy,
    super.key,
  });

  final VoidCallback onAgree;
  final VoidCallback onOpenPrivacy;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenYouTubeTerms;
  final VoidCallback onOpenGooglePrivacy;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    Widget link(String key, String label, VoidCallback onTap) => Semantics(
      link: true,
      child: TextButton(
        key: Key(key),
        style: TextButton.styleFrom(
          minimumSize: const Size(
            AppDimens.minTouchTarget,
            AppDimens.minTouchTarget,
          ),
          alignment: AlignmentDirectional.centerStart,
        ),
        onPressed: onTap,
        child: Text(
          label,
          style: AppTextStyles.body.copyWith(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
            decoration: TextDecoration.underline,
          ),
        ),
      ),
    );
    return AppScaffold(
      leading: const SizedBox.shrink(),
      padBottom: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ListView(
              padding: EdgeInsetsDirectional.symmetric(
                horizontal: AppDimens.md,
              ),
              children: [
                SizedBox(height: AppDimens.sm),
                Semantics(
                  header: true,
                  child: Text(
                    l10n.consentTitle,
                    style: AppTextStyles.headline.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox(height: AppDimens.sm2),
                Text(
                  l10n.consentBody,
                  style: AppTextStyles.body.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                SizedBox(height: AppDimens.md),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      link('consent_privacy', l10n.legalPrivacy, onOpenPrivacy),
                      link('consent_terms', l10n.legalTerms, onOpenTerms),
                      link(
                        'consent_youtube_terms',
                        l10n.legalYouTubeTerms,
                        onOpenYouTubeTerms,
                      ),
                      link(
                        'consent_google_privacy',
                        l10n.legalGooglePrivacy,
                        onOpenGooglePrivacy,
                      ),
                    ],
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
                spacing: AppDimens.sm,
                children: [
                  Text(
                    l10n.consentNote,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  AppPrimaryButton(
                    key: const Key('consent_agree'),
                    label: l10n.consentAgree,
                    onPressed: onAgree,
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
