import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/gym/domain/entities/solo_import.dart';
import 'package:gym_tracker/features/gym/domain/usecases/import_solo_data.dart';
import 'package:gym_tracker/features/gym/presentation/solo_import_controller.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// Opens "Your earlier workouts on this phone" (design board 3, last phone) and
/// carries out the answer. Asked once, only when there is data.
Future<void> showSoloImportSheet(
  BuildContext context,
  SoloImportCandidates data,
) async {
  await showAppSheet<void>(
    context: context,
    builder: (_) => _SoloImportHost(data: data),
  );
}

class _SoloImportHost extends ConsumerWidget {
  const new({required this.data});

  final SoloImportCandidates data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(soloImportControllerProvider.notifier);
    return SoloImportSheet(
      count: data.sessions.length,
      state: ref.watch(soloImportControllerProvider),
      onConfirm: (choice) {
        switch (choice) {
          case SoloImportChoice.copying:
            unawaited(controller.copy());
          case SoloImportChoice.keep:
            unawaited(
              controller.keep().then((_) {
                if (context.mounted) Navigator.of(context).pop();
              }),
            );
          case SoloImportChoice.skip ||
              SoloImportChoice.undecided ||
              SoloImportChoice.done:
            unawaited(
              controller.skip().then((_) {
                if (context.mounted) Navigator.of(context).pop();
              }),
            );
        }
      },
      onClose: () {
        controller.reset();
        Navigator.of(context).pop();
      },
    );
  }
}

/// The question, the progress, the failure and the "done" message in one sheet.
/// Pure UI. [onConfirm] gets `keep`, `skip` or `copying` (= add to account).
class SoloImportSheet extends StatefulWidget {
  const new({
    required this.count,
    required this.state,
    required this.onConfirm,
    required this.onClose,
    super.key,
  });

  /// Workouts to copy (0 with only a plan).
  final int count;
  final SoloImportState state;
  final ValueChanged<SoloImportChoice> onConfirm;
  final VoidCallback onClose;

  @override
  State<SoloImportSheet> createState() => _SoloImportSheetState();
}

class _SoloImportSheetState extends State<SoloImportSheet> {
  SoloImportChoice _choice = SoloImportChoice.keep;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final state = widget.state;
    final children = switch (state) {
      SoloIdle() => [
        Text(
          widget.count == 0
              ? l10n.soloBodyPlanOnly
              : l10n.soloBody(widget.count),
          style: AppTextStyles.body.copyWith(
            color: palette.textSecondary,
            height: 1.6,
          ),
        ),
        for (final (choice, title, detail) in [
          (SoloImportChoice.keep, l10n.soloKeep, l10n.soloKeepDetail),
          (SoloImportChoice.copying, l10n.soloAdd, l10n.soloAddDetail),
          (SoloImportChoice.skip, l10n.soloSkip, l10n.soloSkipDetail),
        ])
          AppListRow(
            key: Key('solo_${choice.name}'),
            leading: AppRadioMark(selected: _choice == choice),
            title: title,
            detail: detail,
            selected: _choice == choice,
            divider: false,
            onTap: () => setState(() => _choice = choice),
          ),
        AppPrimaryButton(
          key: const Key('solo_confirm'),
          label: l10n.soloConfirm,
          onPressed: () => widget.onConfirm(_choice),
        ),
      ],
      SoloRunning(:final done, :final total) => [
        const LoadingView(size: LoadingSize.card),
        Semantics(
          liveRegion: true,
          child: Text(
            l10n.soloCopying(done, total),
            key: const Key('solo_progress'),
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: palette.textSecondary),
          ),
        ),
      ],
      SoloFailed(:final failure) => [
        Semantics(
          liveRegion: true,
          child: Text(
            l10n.soloFailed,
            key: const Key('solo_failed'),
            style: AppTextStyles.body.copyWith(color: palette.error),
          ),
        ),
        Text(
          failure.message(l10n),
          style: AppTextStyles.caption.copyWith(color: palette.textSecondary),
        ),
        AppPrimaryButton(
          key: const Key('solo_retry'),
          label: l10n.retry,
          onPressed: () => widget.onConfirm(SoloImportChoice.copying),
        ),
        AppSecondaryButton(
          key: const Key('solo_later'),
          label: l10n.soloLater,
          onPressed: widget.onClose,
        ),
      ],
      SoloDone() => [
        Text(
          l10n.soloDoneBody,
          key: const Key('solo_done'),
          style: AppTextStyles.body.copyWith(
            color: palette.textSecondary,
            height: 1.6,
          ),
        ),
        AppPrimaryButton(
          key: const Key('solo_ok'),
          label: l10n.commonOk,
          onPressed: widget.onClose,
        ),
      ],
    };
    final title = state is SoloDone ? l10n.soloDoneTitle : l10n.soloTitle;
    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppDimens.md,
        0,
        AppDimens.md,
        AppDimens.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppDimens.sm2,
        children: [
          Semantics(
            header: true,
            child: Text(
              title,
              style: AppTextStyles.title.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}
