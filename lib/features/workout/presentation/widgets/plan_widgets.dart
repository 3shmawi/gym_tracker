import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_plan.dart';
import 'package:gym_tracker/features/workout/domain/entities/workout_plan.dart';
import 'package:gym_tracker/features/workout/domain/usecases/plan_rules.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// One day or exercise in the plan editor (boards 5.1 and 5.3): drag
/// handle, number, name in both languages, a detail line, an optional
/// badge, and the ⋯ button. Tapping the row opens it.
class PlanRow extends StatelessWidget {
  const new({
    required this.index,
    required this.name,
    required this.detail,
    required this.onTap,
    required this.onMore,
    this.marker,
    this.badge,
    this.locked = false,
    super.key,
  });

  /// 0-based; drives the drag handle.
  final int index;
  final LocalizedName name;
  final String detail;
  final VoidCallback onTap;

  /// Opens the actions sheet; null hides the button (locked rows).
  final VoidCallback? onMore;

  /// Replaces the number (e.g. "A" / "B" for a superset pair).
  final String? marker;
  final Widget? badge;

  /// The day of the workout in progress: no drag handle, a lock instead
  /// of ⋯.
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final lang = Localizations.localeOf(context).languageCode;
    final title = name.of(lang);
    final inPair = marker != null;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Row(
        children: [
          if (locked)
            SizedBox(width: AppDimens.xs)
          else
            ReorderableDragStartListener(
              index: index,
              child: Semantics(
                label: l10n.planDrag(title),
                child: SizedBox(
                  width: 40,
                  height: AppDimens.minTouchTarget,
                  child: Icon(
                    Icons.drag_indicator,
                    color: palette.textTertiary,
                    size: AppDimens.iconMd * 0.85,
                  ),
                ),
              ),
            ),
          Expanded(
            child: MergeSemantics(
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(AppDimens.radiusMd),
                child: Padding(
                  padding: EdgeInsetsDirectional.symmetric(
                    vertical: AppDimens.sm,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: AppDimens.sm2,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: inPair
                              ? Theme.of(context).colorScheme.primary
                              : palette.fillSubtle,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          marker ?? '${index + 1}',
                          style: AppTextStyles.label.copyWith(
                            color: inPair
                                ? Theme.of(context).colorScheme.onPrimary
                                : palette.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          spacing: 2,
                          children: [
                            Wrap(
                              spacing: AppDimens.sm,
                              runSpacing: AppDimens.xs,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  title,
                                  style: AppTextStyles.body.copyWith(
                                    fontWeight: FontWeight.w700,
                                    height: 1.3,
                                    color: palette.textPrimary,
                                  ),
                                ),
                                ?badge,
                              ],
                            ),
                            Text(
                              name.other(lang),
                              style: AppTextStyles.caption.copyWith(
                                color: palette.textSecondary,
                              ),
                            ),
                            Text(
                              detail,
                              style: AppTextStyles.caption.copyWith(
                                color: palette.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (locked)
            SizedBox(
              width: AppDimens.minTouchTarget,
              child: Icon(
                Icons.lock_outline,
                color: palette.textTertiary,
                size: AppDimens.iconMd * 0.85,
              ),
            )
          else if (onMore != null)
            IconButton(
              tooltip: l10n.planOptions(title),
              onPressed: onMore,
              constraints: const BoxConstraints(
                minWidth: AppDimens.minTouchTarget,
                minHeight: AppDimens.minTouchTarget,
              ),
              icon: Icon(Icons.more_horiz, color: palette.textSecondary),
            ),
        ],
      ),
    );
  }
}

/// The thin line joining a superset pair on the day screen.
class SupersetRail extends StatelessWidget {
  const new({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: 52, bottom: AppDimens.xs),
      child: Row(
        spacing: AppDimens.sm,
        children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Icon(Icons.link, size: 16, color: primary),
          Expanded(
            child: Text(
              label,
              style: AppTextStyles.caption.copyWith(
                color: primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The small text next to a screen title: "Saves as you go", "Day 2 of 5".
class PlanSubtitle extends StatelessWidget {
  const new(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: AppTextStyles.caption.copyWith(color: context.palette.textSecondary),
  );
}

/// Asks for a name in both languages (board 5.5). Returns null when
/// cancelled. Either language alone is enough; names are cleaned and
/// checked by [PlanNames].
Future<LocalizedName?> showPlanNameSheet(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  LocalizedName? initial,
  bool autofocus = true,
}) => showAppSheet<LocalizedName>(
  context: context,
  builder: (sheet) => _NameSheet(
    title: title,
    confirmLabel: confirmLabel,
    initial: initial,
    autofocus: autofocus,
  ),
);

class _NameSheet extends StatefulWidget {
  const new({
    required this.title,
    required this.confirmLabel,
    required this.autofocus,
    this.initial,
  });

  final String title;
  final String confirmLabel;
  final LocalizedName? initial;

  /// The Arabic field takes the keyboard when the sheet opens.
  final bool autofocus;

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final _ar = TextEditingController(text: widget.initial?.ar ?? '');
  late final _en = TextEditingController(text: widget.initial?.en ?? '');

  @override
  void dispose() {
    _ar.dispose();
    _en.dispose();
    super.dispose();
  }

  String? _error(BuildContext context, String raw) {
    final l10n = context.l10n;
    return switch (PlanNames.check(raw, required: false)) {
      NameProblem.tooLong => l10n.planNameTooLong(PlanLimits.maxNameLength),
      _ => null,
    };
  }

  LocalizedName? get _name => PlanNames.from(ar: _ar.text, en: _en.text);

  void _submit() {
    final name = _name;
    if (name != null) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final arError = _error(context, _ar.text);
    final enError = _error(context, _en.text);
    final empty =
        PlanNames.clean(_ar.text).isEmpty && PlanNames.clean(_en.text).isEmpty;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppDimens.md,
        0,
        AppDimens.md,
        AppDimens.md + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppDimens.sm2,
          children: [
            Semantics(
              header: true,
              child: Text(
                widget.title,
                style: AppTextStyles.title.copyWith(color: palette.textPrimary),
              ),
            ),
            AppTextField(
              key: const Key('plan_name_ar'),
              label: l10n.planNameAr,
              controller: _ar,
              autofocus: widget.autofocus,
              textDirection: TextDirection.rtl,
              maxLength: PlanLimits.maxNameLength,
              helper: l10n.planNameOneIsEnough,
              error: arError,
              onChanged: (_) => setState(() {}),
            ),
            AppTextField(
              key: const Key('plan_name_en'),
              label: l10n.planNameEn,
              controller: _en,
              textDirection: TextDirection.ltr,
              maxLength: PlanLimits.maxNameLength,
              error: enError,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            if (empty)
              Text(
                l10n.planNameEmpty,
                style: AppTextStyles.caption.copyWith(
                  color: palette.textSecondary,
                ),
              ),
            AppPrimaryButton(
              key: const Key('plan_name_save'),
              label: widget.confirmLabel,
              onPressed: _name == null ? null : _submit,
            ),
            AppSecondaryButton(
              label: l10n.planCancel,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirms a delete (board 5.6). True when confirmed.
Future<bool> showPlanDeleteSheet(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  final confirmed = await showAppSheet<bool>(
    context: context,
    builder: (sheet) {
      final palette = sheet.palette;
      return Padding(
        padding: EdgeInsetsDirectional.fromSTEB(
          AppDimens.md,
          0,
          AppDimens.md,
          AppDimens.md,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: AppDimens.sm2,
            children: [
              ExcludeSemantics(
                child: Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: palette.error.withValues(alpha: 0.16),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.delete_outline, color: palette.error),
                  ),
                ),
              ),
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.title.copyWith(
                    color: palette.textPrimary,
                  ),
                ),
              ),
              Text(
                body,
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(
                  color: palette.textSecondary,
                ),
              ),
              AppDangerButton(
                key: const Key('plan_delete_confirm'),
                label: confirmLabel,
                onPressed: () => Navigator.of(sheet).pop(true),
              ),
              AppSecondaryButton(
                label: sheet.l10n.planCancel,
                onPressed: () => Navigator.of(sheet).pop(false),
              ),
            ],
          ),
        ),
      );
    },
  );
  return confirmed ?? false;
}

/// What the ⋯ sheet offers.
enum PlanAction { rename, superset, moveUp, moveDown, delete }

/// The ⋯ sheet for a day or exercise (board 5.3b). [actions] maps each
/// offered action to whether it is enabled; [superset] is the switch's
/// value when the superset row is offered.
Future<PlanAction?> showPlanActionsSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required Map<PlanAction, bool> actions,
  required String deleteLabel,
  bool superset = false,
  String? supersetDetail,
}) => showAppSheet<PlanAction>(
  context: context,
  builder: (sheet) {
    final l10n = sheet.l10n;
    final palette = sheet.palette;
    Widget row(PlanAction action, IconData icon, String label) {
      final enabled = actions[action] ?? false;
      final danger = action == PlanAction.delete;
      final color = !enabled
          ? palette.textTertiary
          : danger
          ? palette.error
          : palette.textPrimary;
      return InkWell(
        key: Key('plan_action_${action.name}'),
        onTap: enabled ? () => Navigator.of(sheet).pop(action) : null,
        borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        child: Semantics(
          button: true,
          enabled: enabled,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: AppDimens.targetLog),
            child: Row(
              spacing: AppDimens.sm2,
              children: [
                Icon(
                  icon,
                  color: danger && enabled ? color : palette.textSecondary,
                ),
                Expanded(
                  child: Text(
                    label,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppDimens.md,
        0,
        AppDimens.md,
        AppDimens.md,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                title,
                style: AppTextStyles.title.copyWith(color: palette.textPrimary),
              ),
            ),
            Text(
              subtitle,
              style: AppTextStyles.caption.copyWith(
                color: palette.textSecondary,
              ),
            ),
            SizedBox(height: AppDimens.sm),
            if (actions.containsKey(PlanAction.rename))
              row(PlanAction.rename, Icons.edit_outlined, l10n.planRename),
            if (actions.containsKey(PlanAction.superset))
              AppSwitchRow(
                key: const Key('plan_action_superset'),
                label: l10n.planSuperset,
                detail: supersetDetail,
                value: superset,
                onChanged: actions[PlanAction.superset]!
                    ? (_) => Navigator.of(sheet).pop(PlanAction.superset)
                    : null,
              ),
            if (actions.containsKey(PlanAction.moveUp))
              row(PlanAction.moveUp, Icons.arrow_upward, l10n.planMoveUp),
            if (actions.containsKey(PlanAction.moveDown))
              row(PlanAction.moveDown, Icons.arrow_downward, l10n.planMoveDown),
            if (actions.containsKey(PlanAction.delete))
              row(PlanAction.delete, Icons.delete_outline, deleteLabel),
          ],
        ),
      ),
    );
  },
);

/// The card a list of [PlanRow]s sits on, reorderable by the drag handles
/// (and by "Move up / down" in the ⋯ sheet, for screen readers).
class PlanReorderableCard extends StatelessWidget {
  const new({
    required this.itemCount,
    required this.itemId,
    required this.itemBuilder,
    required this.onReorder,
    super.key,
  });

  final int itemCount;

  /// A stable id per item (day or exercise id), so rows keep their state
  /// while they move.
  final String Function(int index) itemId;
  final IndexedWidgetBuilder itemBuilder;

  /// Old and new index, the new one as it is after the move.
  final void Function(int from, int to) onReorder;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppCard(
      child: ReorderableListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: itemCount,
        onReorderItem: onReorder,
        proxyDecorator: (child, index, animation) => Material(
          color: palette.surfaceSolid,
          elevation: 8,
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
          child: child,
        ),
        itemBuilder: (context, i) => KeyedSubtree(
          key: ValueKey('plan_item_${itemId(i)}'),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (i > 0) Divider(height: 1, color: palette.fillSubtle),
              itemBuilder(context, i),
            ],
          ),
        ),
      ),
    );
  }
}

/// Opens [showPlanNameSheet] and passes a valid name on.
Future<void> askName(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  required void Function(LocalizedName name) onName,
  LocalizedName? initial,
}) async {
  final name = await showPlanNameSheet(
    context,
    title: title,
    confirmLabel: confirmLabel,
    initial: initial,
  );
  if (name != null) onName(name);
}

/// Why the plan can't be changed (or only partly): the gym's captain
/// manages it. Shown at the top of the plan screens.
class PlanManagedBanner extends StatelessWidget {
  const new({required this.permissions, super.key});

  final PlanPermissions permissions;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppBanner(
      key: const Key('plan_managed_banner'),
      icon: Icons.lock_outline,
      text: permissions.editTargets
          ? l10n.planTargetsOnlyBody
          : '${l10n.planManagedTitle}. ${l10n.planManagedBody}',
    );
  }
}
