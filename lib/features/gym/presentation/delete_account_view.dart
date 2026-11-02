import 'package:flutter/material.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// "Delete your account for good" (design board 4, last phone). Required by
/// Apple 5.1.1(v) and Google Play, inside the app. Pure UI.
///
/// An owner has to type the name of their gym ([ownedGymName]) before the
/// button works. A sole owner of a gym with members gets a
/// `LastOwnerFailure`: the screen then says what to do first.
class DeleteAccountView extends StatefulWidget {
  const new({
    required this.eraseLocal,
    required this.onEraseLocalChanged,
    required this.onDelete,
    required this.onCancel,
    this.ownedGymName,
    this.busy = false,
    this.failure,
    super.key,
  });

  /// The gym whose name an owner must type; null for everyone else.
  final String? ownedGymName;

  /// "Also delete this phone's workouts" (off by default).
  final bool eraseLocal;
  final ValueChanged<bool> onEraseLocalChanged;
  final bool busy;
  final AppFailure? failure;
  final VoidCallback onDelete;
  final VoidCallback onCancel;

  @override
  State<DeleteAccountView> createState() => _DeleteAccountViewState();
}

class _DeleteAccountViewState extends State<DeleteAccountView> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  bool get _confirmed =>
      widget.ownedGymName == null ||
      _typed.text.trim() == widget.ownedGymName!.trim();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final failure = widget.failure;
    final canDelete = _confirmed && !widget.busy;
    return AppScaffold(
      title: l10n.deleteTitle,
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
                SizedBox(height: AppDimens.xs),
                const Center(
                  child: AppOrb(
                    icon: Icons.delete_outline,
                    tone: AppOrbTone.error,
                    size: 80,
                  ),
                ),
                SizedBox(height: AppDimens.sm2),
                Semantics(
                  header: true,
                  child: Text(
                    l10n.deleteHeadline,
                    textAlign: TextAlign.center,
                    style: AppTextStyles.headline.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: AppDimens.scaled(22),
                    ),
                  ),
                ),
                SizedBox(height: AppDimens.sm2),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Loss(l10n.deleteItemProfile),
                      _Loss(l10n.deleteItemWorkouts),
                      _Loss(l10n.deleteItemPlans),
                    ],
                  ),
                ),
                SizedBox(height: AppDimens.sm),
                AppSwitchRow(
                  key: const Key('delete_erase_local'),
                  label: l10n.deleteEraseLocal,
                  detail: l10n.deleteEraseLocalDetail,
                  value: widget.eraseLocal,
                  onChanged: widget.busy ? null : widget.onEraseLocalChanged,
                ),
                SizedBox(height: AppDimens.sm),
                Text(
                  l10n.deleteWarning,
                  style: AppTextStyles.caption.copyWith(
                    color: palette.textSecondary,
                    height: 1.6,
                  ),
                ),
                if (widget.ownedGymName != null) ...[
                  SizedBox(height: AppDimens.md),
                  Text(
                    l10n.deleteOwnerPrompt(widget.ownedGymName!),
                    style: AppTextStyles.body.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: AppDimens.sm),
                  AppTextField(
                    key: const Key('delete_owner_name'),
                    label: l10n.deleteOwnerLabel,
                    controller: _typed,
                    textInputAction: TextInputAction.done,
                    onChanged: (_) => setState(() {}),
                  ),
                ],
              ],
            ),
          ),
          // Pinned above the buttons: the answer to the tap must be in view,
          // not below the fold of the list.
          if (failure != null)
            Padding(
              padding: EdgeInsetsDirectional.fromSTEB(
                AppDimens.md,
                AppDimens.sm,
                AppDimens.md,
                0,
              ),
              child: _Failure(failure: failure),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: AppDimens.sm2 - 2,
                children: [
                  AppDangerButton(
                    key: const Key('delete_confirm'),
                    style: AppDangerStyle.solid,
                    label: l10n.deleteAction,
                    onPressed: canDelete ? widget.onDelete : null,
                  ),
                  AppSecondaryButton(
                    key: const Key('delete_cancel'),
                    label: l10n.commonCancel,
                    onPressed: widget.busy ? null : widget.onCancel,
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

/// One thing that will be gone (design `.perm` with a red cross).
class _Loss extends StatelessWidget {
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: AppDimens.scaled(40)),
      child: Row(
        spacing: AppDimens.sm2 - 2,
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.close,
              size: AppDimens.scaled(20),
              color: palette.error,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: AppTextStyles.body.copyWith(
                fontSize: AppDimens.scaled(14.5),
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Failure extends StatelessWidget {
  const new({required this.failure});

  final AppFailure failure;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final f = failure;
    if (f is LastOwnerFailure) {
      final names = f.gymNames.join('، ');
      return Semantics(
        liveRegion: true,
        child: Column(
          key: const Key('delete_last_owner'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: AppDimens.xs,
          children: [
            Text(
              l10n.deleteLastOwnerTitle,
              style: AppTextStyles.body.copyWith(
                color: palette.error,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              l10n.deleteLastOwnerBody(names),
              style: AppTextStyles.body.copyWith(color: palette.textSecondary),
            ),
          ],
        ),
      );
    }
    return Semantics(
      liveRegion: true,
      child: Text(
        failure.message(l10n),
        key: const Key('delete_error'),
        style: AppTextStyles.body.copyWith(
          color: palette.error,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
