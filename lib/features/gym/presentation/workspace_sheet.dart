import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/entities/workspace.dart';
import 'package:gym_tracker/features/gym/domain/usecases/refresh_memberships.dart';
import 'package:gym_tracker/features/gym/presentation/widgets/gym_labels.dart';
import 'package:gym_tracker/l10n/l10n.dart';
import 'package:intl/intl.dart';

/// Opens "Where are you training?" (design board 4). [onPick] runs for the
/// chosen workspace, [onJoinAnother] for the last row; the sheet closes
/// either way.
Future<void> showWorkspaceSheet(
  BuildContext context, {
  required GymSnapshot snapshot,
  required ValueChanged<Workspace> onPick,
  required VoidCallback onJoinAnother,
}) => showAppSheet<void>(
  context: context,
  builder: (sheet) => WorkspaceSheet(
    snapshot: snapshot,
    onPick: (workspace) {
      Navigator.of(sheet).pop();
      onPick(workspace);
    },
    onJoinAnother: () {
      Navigator.of(sheet).pop();
      onJoinAnother();
    },
  ),
);

/// One active workspace at a time: Solo or one of the gyms. Ended gyms are
/// listed below with what their setting still allows; neither kind can be
/// opened to log new workouts. Pure UI.
class WorkspaceSheet extends StatelessWidget {
  const new({
    required this.snapshot,
    required this.onPick,
    required this.onJoinAnother,
    super.key,
  });

  final GymSnapshot snapshot;
  final ValueChanged<Workspace> onPick;
  final VoidCallback onJoinAnother;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final active = activeMemberships(snapshot.memberships);
    final ended = endedMemberships(snapshot.memberships);
    final inSolo = snapshot.workspace is SoloWorkspace;
    final currentId = switch (snapshot.workspace) {
      GymWorkspace(:final membershipId) => membershipId,
      SoloWorkspace() => null,
    };
    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppDimens.md,
        0,
        AppDimens.md,
        AppDimens.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.switchTitle,
              style: AppTextStyles.title.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          SizedBox(height: AppDimens.xs),
          AppListRow(
            key: const Key('workspace_solo'),
            leading: const AppLogoTile.icon(Icons.person_outline),
            title: l10n.switchSolo,
            detail: l10n.switchSoloDetail,
            selected: inSolo,
            trailing: AppRadioMark(selected: inSolo),
            onTap: () => onPick(const SoloWorkspace()),
          ),
          for (final (i, m) in active.indexed)
            AppListRow(
              key: Key('workspace_${m.id}'),
              leading: AppLogoTile(initials: m.gym.initials, colorIndex: i),
              title: m.gym.name,
              detail: roleLabel(l10n, m.role),
              selected: m.id == currentId,
              trailing: AppRadioMark(selected: m.id == currentId),
              onTap: () => onPick(GymWorkspace(m.id)),
            ),
          AppListRow(
            key: const Key('workspace_join_another'),
            leading: const AppLogoTile.icon(Icons.add),
            title: l10n.switchJoinAnother,
            divider: false,
            onTap: onJoinAnother,
          ),
          if (ended.isNotEmpty) ...[
            AppSectionLabel(l10n.switchEndedHeader),
            for (final (i, m) in ended.indexed)
              _EndedRow(membership: m, last: i == ended.length - 1),
            SizedBox(height: AppDimens.sm),
            Text(
              l10n.switchLockedNote,
              textAlign: TextAlign.center,
              style: AppTextStyles.caption.copyWith(
                color: palette.textSecondary,
                height: 1.6,
              ),
            ),
          ],
          SizedBox(height: AppDimens.sm),
          Text(
            l10n.switchFootnote,
            textAlign: TextAlign.center,
            style: AppTextStyles.caption.copyWith(color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _EndedRow extends StatelessWidget {
  const new({required this.membership, required this.last});

  final Membership membership;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locked = membership.isLocked;
    final endedAt = membership.endedAt?.toLocal();
    final date = endedAt == null
        ? null
        : DateFormat.yMMMd(Localizations.localeOf(context).toString())
              .format(endedAt);
    final detail = switch ((locked, date)) {
      (true, final String d) => l10n.switchEndedLocked(d),
      (true, null) => l10n.switchEndedLockedNoDate,
      (false, final String d) => l10n.switchEndedReadable(d),
      (false, null) => l10n.switchEndedReadableNoDate,
    };
    return AppListRow(
      key: Key('workspace_ended_${membership.id}'),
      leading: AppLogoTile(initials: membership.gym.initials, colorIndex: 1),
      title: membership.gym.name,
      detail: detail,
      divider: !last,
      trailing: AppBadge(
        label: locked ? l10n.switchLocked : l10n.switchReadOnly,
        tone: locked ? AppTone.down : AppTone.keep,
      ),
      muted: locked,
    );
  }
}
