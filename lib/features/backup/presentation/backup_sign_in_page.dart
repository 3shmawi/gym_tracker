import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/features/backup/presentation/backup_sign_in_controller.dart';
import 'package:gym_tracker/features/backup/presentation/backup_sign_in_view.dart';

/// `/backup`: turns backup on (email, code, done). Behind the
/// `training_backup` flag (the router sends everyone home while it is off).
class BackupSignInPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<BackupSignInPage> createState() => _BackupSignInPageState();
}

class _BackupSignInPageState extends ConsumerState<BackupSignInPage> {
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  /// One repaint a second while the "send a new code" countdown runs.
  void _syncTick(BackupSignInController controller) {
    if (controller.resendIn() > 0) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (controller.resendIn() == 0) {
          _tick?.cancel();
          _tick = null;
        }
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(backupSignInProvider);
    final controller = ref.read(backupSignInProvider.notifier);
    _syncTick(controller);
    return BackupSignInView(
      step: state.step,
      email: state.email,
      busy: state.busy,
      problem: state.problem,
      resendIn: controller.resendIn(),
      onSubmitEmail: (email) => unawaited(controller.submitEmail(email)),
      onSubmitCode: (code) => unawaited(controller.submitCode(code)),
      onResend: () => unawaited(controller.resend()),
      onChangeEmail: controller.changeEmail,
      onUseExisting: () => unawaited(controller.useExistingAccount()),
      restored: state.restored,
      onMergeYes: () => unawaited(controller.mergeYes()),
      onMergeNo: () => unawaited(controller.mergeNo()),
      onRetryRestore: () => unawaited(controller.retryRestore()),
      onChoosePlan: (choice) => unawaited(controller.choosePlan(choice)),
      onDone: () => context.pop(),
    );
  }
}
