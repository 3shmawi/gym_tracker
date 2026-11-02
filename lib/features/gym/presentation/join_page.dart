import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gym_tracker/features/gym/domain/entities/invite_code.dart';
import 'package:gym_tracker/features/gym/presentation/join_submit.dart';
import 'package:gym_tracker/features/gym/presentation/join_view.dart';

/// `/join` and `/join/<code>`. [rawCode] is the untrusted text from the link;
/// it is parsed here and only a valid [InviteCode] reaches the screen.
/// Opening a link never joins: that needs the member's tap
/// (`joinSubmitProvider`).
class JoinPage extends ConsumerWidget {
  const new({this.rawCode, super.key});

  final String? rawCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = InviteCode.tryParse(rawCode);
    final submit = ref.watch(joinSubmitProvider);
    // A new link while the screen is open must start the screen over: the key
    // makes Flutter drop the old field instead of keeping its old code.
    return JoinView(
      key: ValueKey(rawCode),
      initialCode: code?.value ?? '',
      fromLink: rawCode != null,
      linkIncomplete: rawCode != null && code == null,
      onSubmit: submit == null ? null : (code) => submit(code).ignore(),
    );
  }
}
