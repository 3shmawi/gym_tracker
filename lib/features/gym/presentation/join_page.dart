import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/features/gym/domain/entities/invite_code.dart';
import 'package:gym_tracker/features/gym/presentation/join_controller.dart';
import 'package:gym_tracker/features/gym/presentation/join_submit.dart';
import 'package:gym_tracker/features/gym/presentation/join_view.dart';
import 'package:gym_tracker/features/gym/presentation/widgets/join_outcome_sheet.dart';

/// `/join` and `/join/<code>`. [rawCode] is the untrusted text from the link;
/// it is parsed here and only a valid [InviteCode] reaches the screen.
/// Opening a link never joins: that needs the member's tap
/// (`joinSubmitProvider`).
class JoinPage extends ConsumerStatefulWidget {
  const new({this.rawCode, super.key});

  final String? rawCode;

  @override
  ConsumerState<JoinPage> createState() => _JoinPageState();
}

class _JoinPageState extends ConsumerState<JoinPage> {
  /// "Type another code": the field starts empty, link or not.
  var _cleared = false;
  var _generation = 0;
  InviteCode? _lastTyped;

  @override
  void initState() {
    super.initState();
    // An outcome from an earlier try must not show on a fresh screen.
    unawaited(
      Future<void>.microtask(() {
        if (mounted) ref.read(joinControllerProvider.notifier).reset();
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final code = _cleared ? null : InviteCode.tryParse(widget.rawCode);
    final submit = ref.watch(joinSubmitProvider);
    final state = ref.watch(joinControllerProvider);
    ref.listen(joinControllerProvider, (_, next) {
      switch (next) {
        case JoinDone():
          context.go(AppRoutes.joined);
        case JoinRefused(:final failure):
          unawaited(_explain(failure));
        case JoinIdle() || JoinSubmitting():
      }
    });
    // A new link while the screen is open must start the screen over: the key
    // makes Flutter drop the old field instead of keeping its old code.
    return JoinView(
      key: ValueKey((widget.rawCode, _generation)),
      initialCode: code?.value ?? '',
      fromLink: widget.rawCode != null && !_cleared,
      linkIncomplete:
          widget.rawCode != null &&
          !_cleared &&
          InviteCode.tryParse(widget.rawCode) == null,
      busy: state is JoinSubmitting,
      invalid:
          state is JoinRefused &&
          JoinOutcome.of(state.failure) == JoinOutcome.invalid,
      onEdited: () => ref.read(joinControllerProvider.notifier).reset(),
      // A link opened cold has no screen behind it.
      onBack: context.canPop() ? null : () => context.go(AppRoutes.home),
      onSubmit: submit == null
          ? null
          : (typed) {
              _lastTyped = typed;
              unawaited(
                submit(typed, typed == code ? JoinVia.link : JoinVia.code),
              );
            },
    );
  }

  /// A wrong code is shown in the field; every other reason (expired, used,
  /// offline, too many tries) is a sheet, like the scanner's.
  Future<void> _explain(AppFailure failure) async {
    final outcome = JoinOutcome.of(failure);
    if (outcome == JoinOutcome.invalid) return;
    final action = await showJoinOutcomeSheet(context, outcome: outcome);
    if (!mounted) return;
    ref.read(joinControllerProvider.notifier).reset();
    final retryable =
        outcome == JoinOutcome.offline || outcome == JoinOutcome.error;
    if (action == JoinOutcomeAction.primary && retryable) {
      final again = _lastTyped;
      final submit = ref.read(joinSubmitProvider);
      if (again != null && submit != null) {
        unawaited(submit(again, JoinVia.code));
      }
    } else if (action == JoinOutcomeAction.secondary) {
      setState(() {
        _cleared = true;
        _generation++;
      });
    }
  }
}
