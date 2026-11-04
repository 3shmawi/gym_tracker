import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/gym/domain/entities/catalog_picture.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_media.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// Callbacks of the picture picker.
class ChoosePicturesActions {
  const new({
    required this.onSearch,
    required this.onToggle,
    required this.onSave,
    required this.onRetry,
    this.onRemoveAll,
  });

  final ValueChanged<String> onSearch;
  final ValueChanged<CatalogPicture> onToggle;
  final VoidCallback onSave;
  final VoidCallback onRetry;

  /// Null when nothing is chosen yet.
  final VoidCallback? onRemoveAll;
}

/// A solo member picks up to 6 pictures for an exercise from the shared
/// library, like a captain does in the dashboard (field test 2026-11-03).
/// The first chosen is the cover. Data + callbacks only.
class ChoosePicturesView extends StatelessWidget {
  const new({
    required this.exerciseName,
    required this.query,
    required this.results,
    required this.chosen,
    required this.image,
    required this.offline,
    required this.saving,
    required this.actions,
    super.key,
  });

  final String exerciseName;
  final TextEditingController query;

  /// null: nothing searched yet.
  final AsyncValue<List<CatalogPicture>>? results;

  /// Chosen public ids, in order (first = cover).
  final List<String> chosen;
  final ImageProvider? Function(String publicId) image;
  final bool offline;
  final bool saving;
  final ChoosePicturesActions actions;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final results = this.results;
    final Widget body;
    if (offline && results is! AsyncData) {
      body = _Message(
        icon: Icons.wifi_off_rounded,
        text: l10n.picturesNeedInternet,
      );
    } else {
      body = switch (results) {
        null => _Message(
          icon: Icons.image_search_rounded,
          text: l10n.picturesSearchHint,
        ),
        AsyncData(value: final list) when list.isEmpty => _Message(
          icon: Icons.image_not_supported_outlined,
          text: l10n.picturesNoResults,
        ),
        AsyncData(value: final list) => _Grid(
          pictures: list,
          chosen: chosen,
          image: image,
          onToggle: actions.onToggle,
        ),
        AsyncError(:final error) => _Message(
          icon: Icons.error_outline_rounded,
          text: (error is AppFailure ? error : UnknownFailure(error)).message(
            l10n,
          ),
          action: AppSecondaryButton(
            key: const Key('pictures_retry'),
            label: l10n.retry,
            onPressed: actions.onRetry,
          ),
        ),
        _ => const _Loading(),
      };
    }
    final full = chosen.length >= GymMedia.maxPicturesPerExercise;
    return Padding(
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
          // The buttons stay put; everything else scrolls, so large text on a
          // small phone never squeezes the results under them.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppDimens.sm2,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.picturesChooseTitle,
                      style: AppTextStyles.title.copyWith(
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    exerciseName,
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  AppTextField(
                    key: const Key('pictures_search'),
                    label: l10n.picturesSearchLabel,
                    controller: query,
                    textInputAction: TextInputAction.search,
                    onSubmitted: actions.onSearch,
                  ),
                  Text(
                    full
                        ? l10n.picturesChosenFull(
                            GymMedia.maxPicturesPerExercise,
                          )
                        : l10n.picturesChosenCount(
                            chosen.length,
                            GymMedia.maxPicturesPerExercise,
                          ),
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
                  body,
                ],
              ),
            ),
          ),
          AppPrimaryButton(
            key: const Key('pictures_save'),
            icon: Icons.check,
            label: l10n.picturesSave,
            onPressed: saving ? null : actions.onSave,
          ),
          if (actions.onRemoveAll case final remove?)
            AppSecondaryButton(
              key: const Key('pictures_remove_all'),
              label: l10n.picturesRemoveAll,
              onPressed: saving ? null : remove,
            ),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const new({
    required this.pictures,
    required this.chosen,
    required this.image,
    required this.onToggle,
  });

  final List<CatalogPicture> pictures;
  final List<String> chosen;
  final ImageProvider? Function(String publicId) image;
  final ValueChanged<CatalogPicture> onToggle;

  @override
  Widget build(BuildContext context) {
    final columns = MediaQuery.sizeOf(context).width >= 600 ? 5 : 3;
    return GridView.count(
      key: const Key('pictures_grid'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: columns,
      mainAxisSpacing: AppDimens.sm,
      crossAxisSpacing: AppDimens.sm,
      children: [
        for (final p in pictures)
          _PictureTile(
            picture: p,
            image: image(p.publicId),
            order: chosen.indexOf(p.publicId),
            full: chosen.length >= GymMedia.maxPicturesPerExercise,
            onTap: () => onToggle(p),
          ),
      ],
    );
  }
}

/// A short message in the results area (idle, nothing found, offline,
/// failed): compact, so the pinned buttons never cover it.
class _Message extends StatelessWidget {
  const new({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(vertical: AppDimens.md),
      child: Column(
        spacing: AppDimens.sm,
        children: [
          Icon(icon, size: AppDimens.iconMd, color: palette.textSecondary),
          Text(
            text,
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: palette.textSecondary),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// Six grey tiles where the pictures will be (no spinner).
class _Loading extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) {
    final fill = context.palette.fillSubtle;
    final columns = MediaQuery.sizeOf(context).width >= 600 ? 5 : 3;
    return Semantics(
      label: context.l10n.loading,
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: columns,
        mainAxisSpacing: AppDimens.sm,
        crossAxisSpacing: AppDimens.sm,
        children: [
          for (var i = 0; i < 6; i++)
            DecoratedBox(
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(AppDimens.radiusMd),
              ),
            ),
        ],
      ),
    );
  }
}

class _PictureTile extends StatelessWidget {
  const new({
    required this.picture,
    required this.image,
    required this.order,
    required this.full,
    required this.onTap,
  });

  final CatalogPicture picture;
  final ImageProvider? image;

  /// Position among the chosen (0 = cover); -1 when not chosen.
  final int order;
  final bool full;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final scheme = Theme.of(context).colorScheme;
    final selected = order >= 0;
    final enabled = selected || !full;
    final frame = picture.frame == 'tension'
        ? l10n.picturesFrameStart
        : l10n.picturesFrameEnd;
    final radius = BorderRadius.circular(AppDimens.radiusMd);
    final pic = image;
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: [
        if (picture.title.isNotEmpty) picture.title,
        frame,
        if (selected) l10n.picturesChosenNumber(order + 1),
      ].join(', '),
      excludeSemantics: true,
      child: Material(
        color: palette.fillSubtle,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: enabled ? onTap : null,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected ? scheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
            padding: EdgeInsets.all(AppDimens.xs),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (pic != null)
                  Opacity(
                    opacity: enabled ? 1 : 0.4,
                    child: Image(
                      image: pic,
                      fit: BoxFit.contain,
                      color: palette.textPrimary,
                      colorBlendMode: BlendMode.srcIn,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                if (selected)
                  PositionedDirectional(
                    top: 0,
                    end: 0,
                    child: Container(
                      width: AppDimens.scaled(24),
                      height: AppDimens.scaled(24),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${order + 1}',
                        style: AppTextStyles.label.copyWith(
                          color: scheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
