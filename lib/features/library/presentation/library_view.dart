import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/library/domain/entities/library_exercise.dart';
import 'package:gym_tracker/features/library/presentation/library_labels.dart';
import 'package:gym_tracker/features/library/presentation/widgets/exercise_illustration.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// The exercise library: search, muscle chips, an equipment filter and the
/// list (board "Library picker"). Pure UI: the page owns the filters. The
/// library is bundled with the app, so there is no loading, error or offline
/// state of its own (the global offline banner still shows).
class LibraryView extends StatelessWidget {
  const new({
    required this.exercises,
    required this.query,
    required this.muscle,
    required this.equipment,
    required this.addedIds,
    required this.dayName,
    required this.onQueryChanged,
    required this.onMuscle,
    required this.onEquipment,
    required this.onOpen,
    required this.onAdd,
    required this.onWriteOwn,
    super.key,
  });

  /// The exercises that fit the filters.
  final List<LibraryExercise> exercises;
  final String query;
  final MuscleGroup? muscle;
  final Equipment? equipment;

  /// Ids already in the day, shown as "Added".
  final Set<String> addedIds;

  /// The day the exercise would go to, for the title.
  final String dayName;

  final ValueChanged<String> onQueryChanged;
  final ValueChanged<MuscleGroup?> onMuscle;
  final ValueChanged<Equipment?> onEquipment;
  final ValueChanged<String> onOpen;
  final ValueChanged<String> onAdd;

  /// The fallback: write the exercise yourself, starting from [query].
  final ValueChanged<String> onWriteOwn;

  Future<void> _pickEquipment(BuildContext context) async {
    final l10n = context.l10n;
    final picked = await showAppSheet<_EquipmentPick>(
      context: context,
      builder: (sheet) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  AppDimens.md,
                  0,
                  AppDimens.md,
                  AppDimens.sm,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Semantics(
                    header: true,
                    child: Text(
                      l10n.libraryEquipmentTitle,
                      style: AppTextStyles.title.copyWith(
                        color: sheet.palette.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
              AppChoiceRow(
                label: l10n.libraryAnyEquipment,
                selected: equipment == null,
                onTap: () =>
                    Navigator.of(sheet).pop(const _EquipmentPick(null)),
              ),
              for (final e in Equipment.values)
                AppChoiceRow(
                  label: equipmentLabel(l10n, e),
                  selected: equipment == e,
                  onTap: () => Navigator.of(sheet).pop(_EquipmentPick(e)),
                ),
              SizedBox(height: AppDimens.md),
            ],
          ),
        ),
      ),
    );
    if (picked != null) onEquipment(picked.value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final equipmentName = equipment == null
        ? l10n.libraryAnyEquipment
        : equipmentLabel(l10n, equipment!);
    return AppScaffold(
      title: l10n.libraryTitle,
      body: ListView(
        padding: EdgeInsetsDirectional.fromSTEB(
          AppDimens.md,
          AppDimens.xs,
          AppDimens.md,
          AppDimens.md,
        ),
        children: [
          _SearchField(initial: query, onChanged: onQueryChanged),
          SizedBox(height: AppDimens.sm),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: AppDimens.sm,
              children: [
                AppChoiceChip(
                  key: const Key('muscle_all'),
                  label: l10n.libraryAll,
                  selected: muscle == null,
                  onTap: () => onMuscle(null),
                ),
                for (final m in MuscleGroup.values)
                  AppChoiceChip(
                    key: Key('muscle_${m.name}'),
                    label: muscleLabel(l10n, m),
                    selected: muscle == m,
                    onTap: () => onMuscle(m),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.libraryCount(exercises.length),
                  style: AppTextStyles.caption.copyWith(
                    color: palette.textSecondary,
                  ),
                ),
              ),
              TextButton.icon(
                key: const Key('equipment_filter'),
                onPressed: () => unawaited(_pickEquipment(context)),
                iconAlignment: IconAlignment.end,
                icon: Icon(Icons.arrow_drop_down, size: AppDimens.iconMd),
                label: Text(equipmentName),
                style: TextButton.styleFrom(
                  minimumSize: const Size(
                    AppDimens.minTouchTarget,
                    AppDimens.minTouchTarget,
                  ),
                  textStyle: AppTextStyles.caption.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (exercises.isEmpty)
            _NoResults(query: query, onWriteOwn: onWriteOwn)
          else ...[
            AppCard(
              child: Column(
                children: [
                  for (final (i, e) in exercises.indexed)
                    _ExerciseRow(
                      exercise: e,
                      added: addedIds.contains(e.id),
                      divider: i < exercises.length - 1,
                      onOpen: () => onOpen(e.id),
                      onAdd: () => onAdd(e.id),
                    ),
                ],
              ),
            ),
            SizedBox(height: AppDimens.sm2),
            AppSecondaryButton(
              key: const Key('library_write_own'),
              label: l10n.libraryCustom,
              onPressed: () => onWriteOwn(query),
            ),
          ],
        ],
      ),
    );
  }
}

class _EquipmentPick {
  const new(this.value);

  final Equipment? value;
}

class _SearchField extends StatefulWidget {
  const new({required this.initial, required this.onChanged});

  final String initial;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      spacing: AppDimens.xs,
      children: [
        Expanded(
          child: AppTextField(
            key: const Key('library_search'),
            label: l10n.librarySearchLabel,
            helper: l10n.librarySearchHint,
            controller: _controller,
            textInputAction: TextInputAction.search,
            onChanged: widget.onChanged,
          ),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: _controller,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : AppIconButton(
                  key: const Key('library_clear'),
                  tooltip: l10n.libraryClearSearch,
                  icon: Icons.close,
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged('');
                  },
                ),
        ),
      ],
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const new({
    required this.exercise,
    required this.added,
    required this.divider,
    required this.onOpen,
    required this.onAdd,
  });

  final LibraryExercise exercise;
  final bool added;
  final bool divider;
  final VoidCallback onOpen;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final lang = Localizations.localeOf(context).languageCode;
    final name = exercise.name;
    final muscle = muscleLabel(l10n, exercise.muscle);
    final meta = '$muscle · ${equipmentList(l10n, exercise.equipment)}';
    return AppListRow(
      key: Key('library_row_${exercise.id}'),
      leading: ExerciseIllustration(exercise: exercise),
      title: name.of(lang),
      detail: [name.other(lang), meta].join('\n'),
      onTap: onOpen,
      divider: divider,
      trailing: added
          ? AppBadge(label: l10n.libraryAdded, tone: AppTone.neutral)
          : Semantics(
              button: true,
              label: l10n.libraryAddLabel(name.of(lang)),
              excludeSemantics: true,
              child: SizedBox(
                width: AppDimens.scaled(96),
                child: AppSecondaryButton(
                  key: Key('library_add_${exercise.id}'),
                  label: l10n.libraryAdd,
                  onPressed: onAdd,
                ),
              ),
            ),
    );
  }
}

class _NoResults extends StatelessWidget {
  const new({required this.query, required this.onWriteOwn});

  static const _maxShown = 24;

  final String query;
  final ValueChanged<String> onWriteOwn;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final trimmed = query.trim();
    // A long query must not turn the button into a wall of text.
    final shown = trimmed.runes.length > _maxShown
        ? '${String.fromCharCodes(trimmed.runes.take(_maxShown))}…'
        : trimmed;
    return EmptyView(
      icon: Icons.search_off,
      message: l10n.libraryNoResultsTitle,
      detail: l10n.libraryNoResultsBody,
      action: AppPrimaryButton(
        key: const Key('library_write_query'),
        label: shown.isEmpty
            ? l10n.libraryWriteOwn
            : l10n.libraryWriteQuery(shown),
        onPressed: () => onWriteOwn(query),
      ),
    );
  }
}
