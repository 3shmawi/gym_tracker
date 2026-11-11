import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gym_tracker/core/adaptive/adaptive.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/theme/azm_theme.dart';
import 'package:gym_tracker/core/update/update_info.dart';
import 'package:gym_tracker/l10n/l10n.dart';
import 'package:url_launcher/url_launcher.dart';

/// Shows the optional ("Update" / "Later") or forced ("Update" only) dialog.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showAdaptiveDialog<void>(
    context: context,
    barrierDismissible: !info.isForce,
    builder: (context) => AzmTheme(child: UpdateDialog(info: info)),
  );
}

class UpdateDialog extends StatelessWidget {
  const new({required this.info, super.key});

  final UpdateInfo info;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final changelog = isArabic
        ? info.config.changelogAr
        : info.config.changelogEn;

    return PopScope(
      canPop: !info.isForce,
      child: AlertDialog.adaptive(
        title: Text(
          info.isForce ? l10n.updateForceTitle : l10n.updateOptionalTitle,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (info.isForce) ...[
                Text(l10n.updateForceMessage),
                SizedBox(height: AppDimens.sm),
              ],
              Text(
                l10n.updateVersions(
                  info.current.toString(),
                  info.config.latest.toString(),
                ),
              ),
              if (changelog.isNotEmpty) ...[
                SizedBox(height: AppDimens.md),
                Text(l10n.updateWhatsNew, style: AppTextStyles.label),
                SizedBox(height: AppDimens.xs),
                Text(changelog),
              ],
            ],
          ),
        ),
        actions: [
          if (!info.isForce)
            AdaptiveDialogAction(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(l10n.updateLater),
            ),
          AdaptiveDialogAction(
            isDefault: true,
            onPressed: () => unawaited(_openStore(info.config.storeUrl)),
            child: Text(l10n.updateNow),
          ),
        ],
      ),
    );
  }

  Future<void> _openStore(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}
