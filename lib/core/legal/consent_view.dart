import 'package:flutter/material.dart';
import 'package:gym_tracker/core/legal/legal_links_row.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// The one-time sheet "Before you start" (YouTube API Services Developer
/// Policies III.A: users agree to the privacy policy before using the app;
/// the terms bind them to YouTube's Terms of Service). New members agree on
/// the welcome screen instead. Pure UI.
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
    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppDimens.md,
        0,
        AppDimens.md,
        AppDimens.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppDimens.sm,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.consentTitle,
              style: AppTextStyles.title.copyWith(color: palette.textPrimary),
            ),
          ),
          Text(
            l10n.consentBody,
            style: AppTextStyles.body.copyWith(color: palette.textSecondary),
          ),
          LegalLinksRow(
            links: [
              LegalLink('consent_privacy', l10n.legalPrivacy, onOpenPrivacy),
              LegalLink('consent_terms', l10n.legalTerms, onOpenTerms),
              LegalLink(
                'consent_youtube_terms',
                l10n.legalYouTubeTerms,
                onOpenYouTubeTerms,
              ),
              LegalLink(
                'consent_google_privacy',
                l10n.legalGooglePrivacy,
                onOpenGooglePrivacy,
              ),
            ],
          ),
          AppPrimaryButton(
            key: const Key('consent_agree'),
            label: l10n.consentAgree,
            onPressed: onAgree,
          ),
        ],
      ),
    );
  }
}
