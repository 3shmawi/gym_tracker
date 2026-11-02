import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_role.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/presentation/widgets/gym_labels.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// "Welcome to {gym}" (design board 3, last phone): the gym's logo, what the
/// member may change in their plan, and one line about privacy. Pure UI.
class JoinedView extends StatelessWidget {
  const new({required this.joined, required this.onStart, super.key});

  final JoinedGym joined;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final permissions = joined.permissions;
    final trainee = joined.role == GymRole.trainee;
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
                SizedBox(height: AppDimens.lg),
                Center(
                  child: AppLogoTile(initials: joined.gym.initials, size: 96),
                ),
                SizedBox(height: AppDimens.sm2),
                Center(child: _JoinedBadge(label: l10n.joinedBadge)),
                SizedBox(height: AppDimens.sm2),
                Semantics(
                  header: true,
                  liveRegion: true,
                  child: Text(
                    l10n.joinedWelcome(joined.gym.name),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headline.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (!trainee) ...[
                  SizedBox(height: AppDimens.xs),
                  Text(
                    roleLabel(l10n, joined.role),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                ],
                SizedBox(height: AppDimens.md),
                if (trainee)
                  AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.joinedPermissionsTitle,
                          style: AppTextStyles.caption.copyWith(
                            color: palette.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        _Permission(
                          label: l10n.joinedPermTargets,
                          allowed:
                              permissions.editTargets || permissions.editPlan,
                        ),
                        _Permission(
                          label: l10n.joinedPermPlan,
                          allowed: permissions.editPlan,
                        ),
                        _Permission(
                          label: l10n.joinedPermOwn,
                          allowed: permissions.buildOwnPlan,
                        ),
                      ],
                    ),
                  ),
                SizedBox(height: AppDimens.sm2),
                Text(
                  l10n.joinedPrivacy,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.caption.copyWith(
                    color: palette.textSecondary,
                    height: 1.6,
                  ),
                ),
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
              child: AppPrimaryButton(
                key: const Key('joined_start'),
                label: l10n.joinedStart,
                onPressed: onStart,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "✓ You joined" (design `.tag2`): a small quiet pill.
class _JoinedBadge extends StatelessWidget {
  const new({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.fillSubtle,
        borderRadius: BorderRadius.circular(AppDimens.scaled(13)),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: AppDimens.scaled(10),
          vertical: AppDimens.xs,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: AppDimens.xs + 1,
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.check,
                size: AppDimens.scaled(20),
                color: palette.textSecondary,
              ),
            ),
            Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: palette.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One thing the member may or may not do (design `.perm`): a green check,
/// or a quiet cross and quieter text.
class _Permission extends StatelessWidget {
  const new({required this.label, required this.allowed});

  final String label;
  final bool allowed;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      container: true,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: AppDimens.scaled(40)),
        child: Row(
          spacing: AppDimens.sm2 - 2,
          children: [
            ExcludeSemantics(
              child: Icon(
                allowed ? Icons.check : Icons.close,
                size: AppDimens.scaled(20),
                color: allowed ? palette.trendUp : palette.textTertiary,
              ),
            ),
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.body.copyWith(
                  fontSize: AppDimens.scaled(14.5),
                  color: allowed ? palette.textPrimary : palette.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
