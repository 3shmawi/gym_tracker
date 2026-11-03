import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// How a new exercise gets into the day.
enum AddExerciseChoice { library, custom }

/// "Add an exercise": pick from the library (the way we suggest) or write one
/// (the fallback, for anything not in the library).
Future<AddExerciseChoice?> showAddExerciseSheet(
  BuildContext context, {
  required String dayName,
  required int exerciseCount,
}) => showAppSheet<AddExerciseChoice>(
  context: context,
  builder: (sheet) {
    final l10n = sheet.l10n;
    final palette = sheet.palette;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            AppDimens.md,
            0,
            AppDimens.md,
            AppDimens.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppDimens.sm2,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.libraryAddSheetTitle,
                  style: AppTextStyles.title.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
              Text(
                l10n.libraryAddSheetBody(dayName, exerciseCount),
                style: AppTextStyles.body.copyWith(
                  color: palette.textSecondary,
                ),
              ),
              AppChoiceCard(
                key: const Key('add_from_library'),
                icon: Icons.search,
                title: l10n.libraryPick,
                detail: l10n.libraryPickBody,
                highlighted: true,
                onTap: () => Navigator.of(sheet).pop(AddExerciseChoice.library),
              ),
              AppChoiceCard(
                key: const Key('add_custom'),
                icon: Icons.edit_outlined,
                title: l10n.libraryWriteOwn,
                detail: l10n.libraryWriteOwnBody,
                onTap: () => Navigator.of(sheet).pop(AddExerciseChoice.custom),
              ),
            ],
          ),
        ),
      ),
    );
  },
);
