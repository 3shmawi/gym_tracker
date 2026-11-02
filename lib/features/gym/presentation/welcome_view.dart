import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// "How do you want to start?" (design board 1, last phone): join a gym or
/// train alone. Two cards of equal weight (join is the green-outlined one),
/// and a link for people who already have a code. Pure UI.
///
/// No account is made by either card: the account is made only when a code
/// is redeemed.
class WelcomeView extends StatelessWidget {
  const new({
    required this.onJoin,
    required this.onSolo,
    required this.onHaveCode,
    super.key,
  });

  final VoidCallback onJoin;
  final VoidCallback onSolo;
  final VoidCallback onHaveCode;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
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
                    l10n.welcomeTitle,
                    style: AppTextStyles.headline.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox(height: AppDimens.sm2),
                Text(
                  l10n.welcomeSubtitle,
                  style: AppTextStyles.body.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
                SizedBox(height: AppDimens.lg),
                AppChoiceCard(
                  key: const Key('welcome_join'),
                  icon: Icons.qr_code_scanner,
                  title: l10n.welcomeJoinTitle,
                  detail: l10n.welcomeJoinBody,
                  highlighted: true,
                  onTap: onJoin,
                ),
                SizedBox(height: AppDimens.sm2),
                AppChoiceCard(
                  key: const Key('welcome_solo'),
                  icon: Icons.person_outline,
                  title: l10n.welcomeSoloTitle,
                  detail: l10n.welcomeSoloBody,
                  onTap: onSolo,
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsetsDirectional.only(bottom: AppDimens.md),
              child: Center(
                child: TextButton(
                  key: const Key('welcome_have_code'),
                  onPressed: onHaveCode,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, AppDimens.minTouchTarget),
                    foregroundColor: Theme.of(context).colorScheme.primary,
                  ),
                  child: Text(
                    l10n.welcomeHaveCode,
                    style: AppTextStyles.label.copyWith(
                      fontSize: AppDimens.scaled(15),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
