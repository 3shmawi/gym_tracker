import 'dart:async';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/gym/domain/entities/invite_code.dart';
import 'package:gym_tracker/features/gym/presentation/join_controller.dart';
import 'package:gym_tracker/features/gym/presentation/join_submit.dart';
import 'package:gym_tracker/features/gym/presentation/scanner_camera.dart';
import 'package:gym_tracker/features/gym/presentation/scanner_view.dart';
import 'package:gym_tracker/features/gym/presentation/widgets/join_outcome_sheet.dart';

/// `/join/scan`: the camera reads the QR and joins at once (the person
/// deliberately scanned, unlike a link). The camera is asked for only when
/// this screen opens; nothing is recorded or kept.
class ScannerPage extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends ConsumerState<ScannerPage> {
  ScannerMode _mode = ScannerMode.live;

  /// A code is being read, checked or explained: new frames are ignored.
  bool _busy = false;
  bool _refused = false;
  InviteCode? _last;

  @override
  void initState() {
    super.initState();
    unawaited(
      Future<void>.microtask(() {
        if (mounted) ref.read(joinControllerProvider.notifier).reset();
      }),
    );
  }

  void _onScanned(String? raw) {
    if (_busy || _mode != ScannerMode.live) return;
    final code = InviteCode.fromScan(raw);
    _busy = true;
    if (code == null) {
      // Not an Azm code (a menu QR, a damaged one): same message as a code
      // the server does not know.
      unawaited(_explain(JoinOutcome.invalid));
      return;
    }
    _last = code;
    unawaited(_join(code));
  }

  Future<void> _join(InviteCode code) async {
    setState(() => _mode = ScannerMode.joining);
    final submit = ref.read(joinSubmitProvider);
    if (submit == null) {
      _busy = false;
      setState(() => _mode = ScannerMode.live);
      return;
    }
    await submit(code, JoinVia.scan);
  }

  Future<void> _explain(JoinOutcome outcome) async {
    if (!mounted) return;
    setState(() {
      _refused = true;
      if (_mode == ScannerMode.joining) _mode = ScannerMode.live;
    });
    final action = await showJoinOutcomeSheet(context, outcome: outcome);
    if (!mounted) return;
    ref.read(joinControllerProvider.notifier).reset();
    setState(() => _refused = false);
    final retryable =
        outcome == JoinOutcome.offline || outcome == JoinOutcome.error;
    if (action == JoinOutcomeAction.secondary) {
      _busy = false;
      context.go(AppRoutes.join);
    } else if (action == JoinOutcomeAction.primary && retryable) {
      final again = _last;
      if (again != null) {
        unawaited(_join(again));
      } else {
        _busy = false;
      }
    } else {
      // "Scan again" / "OK": back to the camera.
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(joinControllerProvider, (_, next) {
      switch (next) {
        case JoinDone():
          context.go(AppRoutes.joined);
        case JoinRefused(:final failure):
          final outcome = JoinOutcome.of(failure);
          if (outcome == JoinOutcome.offline) {
            setState(() => _mode = ScannerMode.offline);
          } else {
            unawaited(_explain(outcome));
          }
        case JoinIdle() || JoinSubmitting():
      }
    });
    final cameraBuilder = ref.watch(scannerCameraBuilderProvider);
    return ScannerView(
      mode: _mode,
      refused: _refused,
      camera: _mode == ScannerMode.live
          ? cameraBuilder(
              context,
              onScanned: _onScanned,
              onProblem: (problem) {
                if (!mounted) return;
                setState(
                  () => _mode = problem == CameraProblem.denied
                      ? ScannerMode.denied
                      : ScannerMode.unavailable,
                );
              },
            )
          : null,
      onClose: () => _leave(context),
      onTypeCode: () => context.go(AppRoutes.join),
      onOpenSettings: () => unawaited(AppSettings.openAppSettings()),
      onRetry: _last == null
          ? () => setState(() {
              _mode = ScannerMode.live;
              _busy = false;
            })
          : () {
              ref.read(joinControllerProvider.notifier).reset();
              unawaited(_join(_last!));
            },
    );
  }

  void _leave(BuildContext context) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.welcome);
    }
  }
}
