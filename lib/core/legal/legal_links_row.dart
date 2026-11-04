import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';

/// A legal page as a link (48 high, underlined, the primary color).
class LegalLink {
  const new(this.key, this.label, this.onTap);

  final String key;
  final String label;
  final VoidCallback onTap;
}

/// Legal links in a row that wraps, centred (the welcome line, the sheet).
class LegalLinksRow extends StatelessWidget {
  const new({required this.links, super.key});

  final List<LegalLink> links;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppDimens.xs,
      children: [
        for (final l in links)
          Semantics(
            link: true,
            child: TextButton(
              key: Key(l.key),
              style: TextButton.styleFrom(
                minimumSize: const Size(
                  AppDimens.minTouchTarget,
                  AppDimens.minTouchTarget,
                ),
                padding: EdgeInsetsDirectional.symmetric(
                  horizontal: AppDimens.sm,
                ),
              ),
              onPressed: l.onTap,
              child: Text(
                l.label,
                style: AppTextStyles.caption.copyWith(
                  color: primary,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: primary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
