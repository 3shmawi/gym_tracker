import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/theme/app_colors.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_palette.dart';
import 'package:gym_tracker/core/theme/app_text_styles.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/gym/domain/entities/account_session.dart';
import 'package:gym_tracker/features/gym/domain/usecases/refresh_memberships.dart';
import 'package:gym_tracker/features/gym/presentation/widgets/gym_labels.dart';
import 'package:gym_tracker/l10n/l10n.dart';

/// "My account" (design board 4, third phone): who is signed in, the gyms,
/// how to switch, and the two separate exits — sign out and delete account.
/// Pure UI.
///
/// [state] is the phone's copy of the gyms, so the screen opens offline; an
/// error carries an `AppFailure` for `ErrorView`.
class ProfileView extends StatelessWidget {
  const new({
    required this.session,
    required this.state,
    required this.onSwitch,
    required this.onSignOut,
    required this.onDelete,
    required this.onRetry,
    this.onAddEmail,
    super.key,
  });

  final AccountSession session;
  final AsyncValue<GymSnapshot> state;
  final VoidCallback onSwitch;
  final VoidCallback onSignOut;
  final VoidCallback onDelete;
  final VoidCallback onRetry;

  /// Starts making an anonymous account permanent. Null hides the card.
  final Future<AppFailure?> Function(String email)? onAddEmail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppScaffold(
      title: l10n.profileTitle,
      padBottom: false,
      body: switch (state) {
        AsyncLoading() => const LoadingView(),
        AsyncError(:final error) => ErrorView(
          failure: AppFailure.from(error),
          onRetry: onRetry,
        ),
        AsyncData(:final value) => _Content(
          session: session,
          snapshot: value,
          onSwitch: onSwitch,
          onSignOut: onSignOut,
          onDelete: onDelete,
          onAddEmail: onAddEmail,
        ),
      },
    );
  }
}

class _Content extends StatelessWidget {
  const new({
    required this.session,
    required this.snapshot,
    required this.onSwitch,
    required this.onSignOut,
    required this.onDelete,
    required this.onAddEmail,
  });

  final AccountSession session;
  final GymSnapshot snapshot;
  final VoidCallback onSwitch;
  final VoidCallback onSignOut;
  final VoidCallback onDelete;
  final Future<AppFailure?> Function(String email)? onAddEmail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    final active = activeMemberships(snapshot.memberships);
    final name = active
        .map((m) => m.displayName)
        .whereType<String>()
        .where((n) => n.trim().isNotEmpty)
        .firstOrNull;
    final summary = active.isEmpty
        ? l10n.profileNoGym
        : l10n.profileMemberOf(active.map((m) => m.gym.name).join('، '));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsetsDirectional.symmetric(horizontal: AppDimens.md),
            children: [
              Row(
                spacing: AppDimens.sm2,
                children: [
                  _Avatar(name: name ?? session.email),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (name != null)
                          Text(
                            name,
                            style: AppTextStyles.title.copyWith(
                              color: palette.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        Text(
                          summary,
                          style: AppTextStyles.caption.copyWith(
                            color: palette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: AppDimens.sm2),
              AppCard(
                child: Column(
                  children: [
                    for (final (i, m) in active.indexed)
                      AppListRow(
                        key: Key('profile_gym_${m.id}'),
                        leading: AppLogoTile(
                          initials: m.gym.initials,
                          colorIndex: i,
                        ),
                        title: m.gym.name,
                        detail: roleLabel(l10n, m.role),
                        trailing: const _Chevron(),
                        onTap: onSwitch,
                      ),
                    AppListRow(
                      key: const Key('profile_switch'),
                      leading: const AppLogoTile.icon(Icons.swap_horiz),
                      title: l10n.profileSwitch,
                      divider: false,
                      trailing: const _Chevron(),
                      onTap: onSwitch,
                    ),
                  ],
                ),
              ),
              SizedBox(height: AppDimens.sm2),
              if (onAddEmail != null && session.isAnonymous) ...[
                _SecureCard(onAddEmail: onAddEmail!),
                SizedBox(height: AppDimens.sm2),
              ],
              Padding(
                padding: EdgeInsetsDirectional.symmetric(
                  horizontal: AppDimens.xs + 2,
                ),
                child: Text(
                  session.email == null
                      ? l10n.profileNoEmail
                      : l10n.profileSignedInAs(session.email!),
                  style: AppTextStyles.caption.copyWith(
                    color: palette.textSecondary,
                    height: 1.6,
                  ),
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
              AppDimens.sm,
              AppDimens.md,
              AppDimens.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: AppDimens.sm2 - 2,
              children: [
                AppSecondaryButton(
                  key: const Key('profile_sign_out'),
                  icon: Icons.logout,
                  label: l10n.profileSignOut,
                  onPressed: onSignOut,
                ),
                AppDangerButton(
                  key: const Key('profile_delete'),
                  style: AppDangerStyle.outlined,
                  icon: Icons.delete_outline,
                  label: l10n.profileDelete,
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Chevron extends StatelessWidget {
  const new();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Icon(
      Icons.chevron_right,
      color: context.palette.textSecondary,
      textDirection: Directionality.of(context),
    ),
  );
}

/// The 64-px circle with the first letter of the name (design `.av`).
class _Avatar extends StatelessWidget {
  const new({required this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final side = AppDimens.scaled(64);
    final letter = name == null || name!.trim().isEmpty
        ? null
        : String.fromCharCodes(name!.trim().runes.take(1)).toUpperCase();
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: side,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
              colors: [AppColors.primary, Color(0xFF0B6B33)],
            ),
          ),
          child: Center(
            child: letter == null
                ? Icon(
                    Icons.person,
                    size: side * 0.5,
                    color: AppColors.onPrimary,
                  )
                : Text(
                    letter,
                    style: AppTextStyles.headline.copyWith(
                      color: AppColors.onPrimary,
                      fontWeight: FontWeight.w800,
                      fontSize: side * 0.4,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// "Secure your account": add an email to an anonymous account.
class _SecureCard extends StatelessWidget {
  const new({required this.onAddEmail});

  final Future<AppFailure?> Function(String email) onAddEmail;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: AppDimens.sm,
        children: [
          Semantics(
            header: true,
            child: Text(
              l10n.profileSecureTitle,
              style: AppTextStyles.body.copyWith(
                color: palette.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            l10n.profileSecureBody,
            style: AppTextStyles.caption.copyWith(
              color: palette.textSecondary,
              height: 1.6,
            ),
          ),
          AppSecondaryButton(
            key: const Key('profile_add_email'),
            icon: Icons.mail_outline,
            label: l10n.profileAddEmail,
            onPressed: () => showAppSheet<void>(
              context: context,
              builder: (_) => AddEmailSheet(onAddEmail: onAddEmail),
            ),
          ),
        ],
      ),
    );
  }
}

/// Asks for an email and sends the confirmation link. Only the shape of the
/// address is checked here; the server decides the rest.
class AddEmailSheet extends StatefulWidget {
  const new({required this.onAddEmail, super.key});

  final Future<AppFailure?> Function(String email) onAddEmail;

  @override
  State<AddEmailSheet> createState() => _AddEmailSheetState();
}

class _AddEmailSheetState extends State<AddEmailSheet> {
  final _controller = TextEditingController();
  bool _busy = false;
  bool _touched = false;
  String? _sentTo;
  AppFailure? _failure;

  static const maxLength = 254;
  // The HTML living standard's address shape, ASCII only: letters, digits and
  // the few punctuation marks a local part may have, then dotted labels.
  static final _shape = RegExp(
    r'''^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@'''
    '[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?'
    r'(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)+$',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _email => _controller.text.trim();
  bool get _valid => _email.length <= maxLength && _shape.hasMatch(_email);

  Future<void> _send() async {
    setState(() => _touched = true);
    if (!_valid || _busy) return;
    final email = _email;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final failure = await widget.onAddEmail(email);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _failure = failure;
      _sentTo = failure == null ? email : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.palette;
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
                l10n.profileSecureTitle,
                style: AppTextStyles.title.copyWith(color: palette.textPrimary),
              ),
            ),
            if (_sentTo != null)
              Semantics(
                liveRegion: true,
                child: AppBanner(
                  key: const Key('add_email_sent'),
                  icon: Icons.mark_email_read_outlined,
                  text: l10n.profileEmailSent(_sentTo!),
                ),
              )
            else ...[
              AppTextField(
                key: const Key('add_email_field'),
                label: l10n.profileEmailLabel,
                controller: _controller,
                textDirection: TextDirection.ltr,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.send,
                error: _touched && !_valid ? l10n.profileEmailInvalid : null,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _send(),
              ),
              if (_failure != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _failure!.message(l10n),
                    style: AppTextStyles.body.copyWith(color: palette.error),
                  ),
                ),
              AppPrimaryButton(
                key: const Key('add_email_send'),
                label: l10n.profileEmailSend,
                onPressed: _busy ? null : _send,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Sign out?" (design board 4, fourth phone). Returns true to sign out. The
/// safe action (stay) is the green button.
Future<bool> confirmSignOut(BuildContext context) async {
  final l10n = context.l10n;
  final palette = context.palette;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialog) => Dialog(
      backgroundColor: palette.surfaceSolid,
      insetPadding: EdgeInsets.all(AppDimens.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDimens.scaled(30)),
      ),
      child: SingleChildScrollView(
        padding: EdgeInsetsDirectional.fromSTEB(
          AppDimens.scaled(20),
          AppDimens.scaled(22),
          AppDimens.scaled(20),
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
                l10n.signOutTitle,
                style: AppTextStyles.title.copyWith(
                  color: palette.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              l10n.signOutBody,
              style: AppTextStyles.body.copyWith(
                color: palette.textSecondary,
                fontSize: AppDimens.scaled(14.5),
                height: 1.65,
              ),
            ),
            AppBanner(
              icon: Icons.warning_amber_rounded,
              tone: AppBannerTone.warning,
              text: l10n.signOutSoloNote,
            ),
            AppPrimaryButton(
              key: const Key('sign_out_stay'),
              label: l10n.signOutStay,
              onPressed: () => Navigator.of(dialog).pop(false),
            ),
            AppDangerButton(
              key: const Key('sign_out_confirm'),
              style: AppDangerStyle.outlined,
              label: l10n.signOutConfirm,
              onPressed: () => Navigator.of(dialog).pop(true),
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}
