import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/features/gym/domain/entities/account_session.dart';
import 'package:gym_tracker/features/gym/domain/entities/gym_role.dart';
import 'package:gym_tracker/features/gym/domain/entities/membership.dart';
import 'package:gym_tracker/features/gym/domain/usecases/refresh_memberships.dart';
import 'package:gym_tracker/features/gym/presentation/profile_view.dart';

import '../../../helpers/gym_fakes.dart';
import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';
import '../../workout/presentation/plan_samples.dart' show SheetHost;

final twoGymSnapshot = GymSnapshot(
  memberships: [
    member(),
    member(id: 'm2', gym: 'Peak Fitness', role: GymRole.captain),
    member(id: 'm3', gym: 'Gold X', status: MembershipStatus.ended),
  ],
);

ProfileView view({
  AccountSession session = anonymousSession,
  AsyncValue<GymSnapshot>? state,
  VoidCallback? onSwitch,
  VoidCallback? onSignOut,
  VoidCallback? onDelete,
  VoidCallback? onRetry,
  Future<AppFailure?> Function(String)? onAddEmail,
}) => ProfileView(
  session: session,
  state: state ?? AsyncData(twoGymSnapshot),
  onSwitch: onSwitch ?? () {},
  onSignOut: onSignOut ?? () {},
  onDelete: onDelete ?? () {},
  onRetry: onRetry ?? () {},
  onAddEmail: onAddEmail,
);

void main() {
  group(ProfileView, () {
    testWidgets('shows who the person is and the gyms they can train in', (
      tester,
    ) async {
      await tester.pumpApp(view());
      expect(find.text('Mohamed'), findsOneWidget);
      expect(
        find.text(l10nEn.profileMemberOf('Iron House، Peak Fitness')),
        findsOneWidget,
      );
      expect(find.text('Gold X'), findsNothing, reason: 'ended: not here');
      expect(find.text(l10nEn.profileNoEmail), findsOneWidget);
    });

    testWidgets('sign out and delete are separate buttons', (tester) async {
      final calls = <String>[];
      await tester.pumpApp(
        view(
          onSignOut: () => calls.add('out'),
          onDelete: () => calls.add('delete'),
          onSwitch: () => calls.add('switch'),
        ),
      );
      await tester.tap(find.byKey(const Key('profile_sign_out')));
      await tester.tap(find.byKey(const Key('profile_delete')));
      await tester.tap(find.byKey(const Key('profile_switch')));
      expect(calls, ['out', 'delete', 'switch']);
    });

    testWidgets('an account with an email shows it, and no add-email card', (
      tester,
    ) async {
      await tester.pumpApp(
        view(session: emailSession, onAddEmail: (_) async => null),
      );
      expect(
        find.text(l10nEn.profileSignedInAs('me@example.com')),
        findsOneWidget,
      );
      expect(find.byKey(const Key('profile_add_email')), findsNothing);
    });

    testWidgets('no gym yet: says so, still has the exits', (tester) async {
      await tester.pumpApp(view(state: const AsyncData(GymSnapshot())));
      expect(find.text(l10nEn.profileNoGym), findsOneWidget);
      expect(find.byKey(const Key('profile_delete')), findsOneWidget);
    });

    testWidgets('loading and error states', (tester) async {
      await tester.pumpApp(view(state: const AsyncLoading()));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.bySemanticsLabel(l10nEn.loading), findsOneWidget);

      var retried = 0;
      await tester.pumpApp(
        view(
          state: const AsyncError(NetworkFailure(), StackTrace.empty),
          onRetry: () => retried++,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10nEn.retry));
      expect(retried, 1);
    });

    testWidgets('meets accessibility guidelines', (tester) async {
      await tester.pumpApp(view(onAddEmail: (_) async => null));
      await tester.expectAccessible();
    });
  });

  group(AddEmailSheet, () {
    Future<List<String>> pumpSheet(
      WidgetTester tester, {
      Future<AppFailure?> Function(String)? onAdd,
    }) async {
      final sent = <String>[];
      await tester.pumpApp(
        Material(
          child: AddEmailSheet(
            onAddEmail: (email) async {
              sent.add(email);
              return onAdd == null ? null : await onAdd(email);
            },
          ),
        ),
      );
      return sent;
    }

    testWidgets('checks the shape, then sends the trimmed address', (
      tester,
    ) async {
      final sent = await pumpSheet(tester);
      await tester.enterText(
        find.byKey(const Key('add_email_field')),
        'not an email',
      );
      await tester.tap(find.byKey(const Key('add_email_send')));
      await tester.pump();
      expect(find.text(l10nEn.profileEmailInvalid), findsOneWidget);
      expect(sent, isEmpty);

      await tester.enterText(
        find.byKey(const Key('add_email_field')),
        '  me@example.com ',
      );
      await tester.tap(find.byKey(const Key('add_email_send')));
      await tester.pumpAndSettle();
      expect(sent, ['me@example.com']);
      expect(
        find.text(l10nEn.profileEmailSent('me@example.com')),
        findsOneWidget,
      );
    });

    testWidgets('hostile and huge input is refused before any call', (
      tester,
    ) async {
      final sent = await pumpSheet(tester);
      for (final text in [
        '',
        '   ',
        '@',
        'a@b',
        'a b@c.d',
        '<script>@x.y</script> ',
        "x'; drop table people;--",
        '${'a' * 300}@example.com',
        'ünï@example.com',
        'me@exa mple.com',
        'me@-example.com',
      ]) {
        await tester.enterText(find.byKey(const Key('add_email_field')), text);
        await tester.tap(find.byKey(const Key('add_email_send')));
        await tester.pump();
      }
      expect(sent, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failure is shown and the person can try again', (
      tester,
    ) async {
      var calls = 0;
      await pumpSheet(
        tester,
        onAdd: (_) async => ++calls == 1 ? const NetworkFailure() : null,
      );
      await tester.enterText(
        find.byKey(const Key('add_email_field')),
        'me@example.com',
      );
      await tester.tap(find.byKey(const Key('add_email_send')));
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.errorNetwork), findsOneWidget);
      await tester.tap(find.byKey(const Key('add_email_send')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('add_email_sent')), findsOneWidget);
    });
  });

  group('confirmSignOut', () {
    Future<bool?> run(WidgetTester tester, String button) async {
      bool? answer;
      await tester.pumpApp(
        SheetHost(
          background: const SizedBox(),
          open: (context) async => answer = await confirmSignOut(context),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.signOutTitle), findsOneWidget);
      await tester.tap(find.byKey(Key(button)));
      await tester.pumpAndSettle();
      return answer;
    }

    testWidgets('staying is the safe, green button', (tester) async {
      expect(await run(tester, 'sign_out_stay'), isFalse);
    });

    testWidgets('only the second button signs out', (tester) async {
      expect(await run(tester, 'sign_out_confirm'), isTrue);
    });

    testWidgets('says it is one-way and that solo workouts stay', (
      tester,
    ) async {
      await tester.pumpApp(
        const SheetHost(background: SizedBox(), open: confirmSignOut),
      );
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.signOutBody), findsOneWidget);
      expect(find.text(l10nEn.signOutSoloNote), findsOneWidget);
    });
  });

  screensUiTests({
    'profile_anonymous': () => view(onAddEmail: (_) async => null),
    'profile_with_email': () => view(session: emailSession),
    'profile_no_gym': () => view(state: const AsyncData(GymSnapshot())),
    'profile_error': () =>
        view(state: const AsyncError(NetworkFailure(), StackTrace.empty)),
    'profile_add_email_sheet': () => SheetHost(
      background: view(onAddEmail: (_) async => null),
      open: (context) => showAppSheet<void>(
        context: context,
        builder: (_) => AddEmailSheet(onAddEmail: (_) async => null),
      ),
    ),
    'profile_sign_out_dialog': () =>
        SheetHost(background: view(), open: confirmSignOut),
  });
}
