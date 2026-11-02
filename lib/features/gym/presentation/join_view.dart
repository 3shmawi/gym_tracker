import 'package:flutter/material.dart';
import 'package:gym_tracker/core/adaptive/adaptive.dart';
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
/// taps Join ([onSubmit]). While [onSubmit] is null the button stays off and a
/// line says so. A refused code shows [invalid] inline (board 3, "Wrong code");
/// the other reasons come as a sheet from the page.
class JoinView extends StatefulWidget {
  const new({
    required this.onSubmit,
    this.busy = false,
    this.invalid = false,
    this.onEdited,
    this.onBack,
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

  /// The code is on its way to the server: the button says so and is off.
  final bool busy;

  /// The server said this code is not right: red boxes and a message.
  final bool invalid;

  /// The member changed the code (a refusal no longer applies).
  final VoidCallback? onEdited;

  /// A back button for when nothing is behind this screen (a cold link).
  final VoidCallback? onBack;

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
    );
    var last = _controller.text;
    _controller.addListener(() {
      setState(() {});
      if (_controller.text != last) {
        last = _controller.text;
        widget.onEdited?.call();
      }
    });
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
    if (widget.invalid) {
      slot = _Slot.invalid;
    } else if (widget.linkIncomplete && _controller.text.isEmpty) {
      slot = _Slot.error;
    } else if (widget.fromLink && untouched && _code != null) {
      slot = _Slot.linkBanner;
    } else {
      slot = _Slot.hint;
    }
    final isError = slot == _Slot.error || slot == _Slot.invalid;
    return AppScaffold(
      leading: widget.onBack == null
          ? null
          : AppIconButton(
              key: const Key('join_back'),
              icon: AdaptiveIcons.back(context),
              tooltip: l10n.commonBack,
              onPressed: widget.onBack!,
            ),
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
                    _Slot.linkBanner => AppBanner(
                      key: const Key('join_message'),
                      icon: Icons.link,
                      text: l10n.joinFromLink,
                    ),
                    _Slot.error || _Slot.invalid => Semantics(
                      liveRegion: true,
                      child: Text(
                        slot == _Slot.invalid
                            ? l10n.joinInvalidInline
                            : l10n.joinLinkIncomplete,
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
                label: widget.busy ? l10n.joinInProgress : l10n.joinAction,
                onPressed:
                    widget.onSubmit != null && _code != null && !widget.busy
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

enum _Slot { hint, linkBanner, error, invalid }
