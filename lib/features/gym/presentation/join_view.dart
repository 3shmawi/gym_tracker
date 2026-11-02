import 'package:flutter/material.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/gym/domain/entities/invite_code.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// "Enter your gym code": six boxes and a Join button (design board 3).
/// Pure UI: the code and what to do with it come in as data and callbacks.
///
/// A link only pre-fills [initialCode]; nothing is submitted until the member
/// taps Join ([onSubmit]). While [onSubmit] is null (joining is not built
/// yet) the button stays off and a line says so.
class JoinView extends StatefulWidget {
  const new({
    required this.onSubmit,
    this.initialCode = '',
    this.fromLink = false,
    this.linkIncomplete = false,
    super.key,
  });

  /// A valid code taken from a link, or '' (typed from scratch).
  final String initialCode;

  /// The screen was opened from an invite link.
  final bool fromLink;

  /// It was opened from a link that held no valid code.
  final bool linkIncomplete;

  final ValueChanged<InviteCode>? onSubmit;

  @override
  State<JoinView> createState() => _JoinViewState();
}

class _JoinViewState extends State<JoinView> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: InviteCode.clean(widget.initialCode),
    )..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  InviteCode? get _code => InviteCode.tryParse(_controller.text);

  void _submit() {
    final code = _code;
    if (code != null) widget.onSubmit?.call(code);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final untouched = _controller.text == InviteCode.clean(widget.initialCode);
    final _Slot slot;
    if (widget.linkIncomplete && _controller.text.isEmpty) {
      slot = _Slot.error;
    } else if (widget.fromLink && untouched && _code != null) {
      slot = _Slot.linkBanner;
    } else {
      slot = _Slot.hint;
    }
    final isError = slot == _Slot.error;
    return AppScaffold(
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
                // Design board 3: the title sits under the back button.
                SizedBox(height: AppDimens.sm),
                Semantics(
                  header: true,
                  child: Text(
                    l10n.joinTitle,
                    style: AppTextStyles.headline.copyWith(
                      color: palette.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                SizedBox(height: AppDimens.scaled(18)),
                AppCodeField(
                  key: const Key('join_code'),
                  label: l10n.joinCodeLabel,
                  controller: _controller,
                  length: InviteCode.length,
                  clean: InviteCode.clean,
                  hasError: isError,
                  autofocus: !widget.fromLink,
                  onSubmitted: (_) => _submit(),
                ),
                SizedBox(height: AppDimens.scaled(18)),
                // One fixed slot: the hint, the link banner and the error
                // swap here, so the boxes never move.
                ConstrainedBox(
                  constraints: BoxConstraints(minHeight: AppDimens.scaled(64)),
                  child: switch (slot) {
                    _Slot.hint => Text(
                      l10n.joinHint,
                      key: const Key('join_message'),
                      style: AppTextStyles.body.copyWith(
                        color: palette.textSecondary,
                        height: 1.6,
                      ),
                    ),
                    _Slot.linkBanner => _LinkBanner(
                      key: const Key('join_message'),
                      text: l10n.joinFromLink,
                    ),
                    _Slot.error => Semantics(
                      liveRegion: true,
                      child: Text(
                        l10n.joinLinkIncomplete,
                        key: const Key('join_message'),
                        textAlign: TextAlign.center,
                        style: AppTextStyles.body.copyWith(
                          color: palette.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  },
                ),
                if (widget.onSubmit == null)
                  Text(
                    l10n.joinNotReady,
                    key: const Key('join_not_ready'),
                    style: AppTextStyles.caption.copyWith(
                      color: palette.textSecondary,
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
                0,
                AppDimens.md,
                AppDimens.md,
              ),
              child: AppPrimaryButton(
                key: const Key('join_submit'),
                label: l10n.joinAction,
                onPressed: widget.onSubmit != null && _code != null
                    ? _submit
                    : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _Slot { hint, linkBanner, error }

/// "We opened the link and typed the code for you" (design `.banner.info`:
/// 18 radius, 10 × 14 padding, link icon, blue tint).
class _LinkBanner extends StatelessWidget {
  const new({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.trendKeep.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppDimens.scaled(18)),
      ),
      child: Padding(
        padding: EdgeInsetsDirectional.symmetric(
          horizontal: AppDimens.scaled(14),
          vertical: AppDimens.scaled(10),
        ),
        child: Row(
          spacing: AppDimens.scaled(10),
          children: [
            ExcludeSemantics(
              child: Icon(
                Icons.link,
                size: AppDimens.scaled(20),
                color: palette.textPrimary,
              ),
            ),
            Expanded(
              child: Text(
                text,
                style: AppTextStyles.body.copyWith(
                  color: palette.textPrimary,
                  fontSize: AppDimens.scaled(13.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
