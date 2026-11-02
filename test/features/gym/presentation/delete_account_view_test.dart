import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/features/gym/presentation/delete_account_view.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';

DeleteAccountView view({
  String? ownedGymName,
  bool eraseLocal = false,
  bool busy = false,
  AppFailure? failure,
  ValueChanged<bool>? onEraseLocalChanged,
  VoidCallback? onDelete,
  VoidCallback? onCancel,
}) => DeleteAccountView(
  ownedGymName: ownedGymName,
  eraseLocal: eraseLocal,
  busy: busy,
  failure: failure,
  onEraseLocalChanged: onEraseLocalChanged ?? (_) {},
  onDelete: onDelete ?? () {},
  onCancel: onCancel ?? () {},
);

void main() {
  group(DeleteAccountView, () {
    testWidgets('lists what is lost and asks once; cancel is separate', (
      tester,
    ) async {
      final calls = <String>[];
      await tester.pumpApp(
        view(
          onDelete: () => calls.add('delete'),
          onCancel: () => calls.add('cancel'),
        ),
      );
      expect(find.text(l10nEn.deleteItemProfile), findsOneWidget);
      expect(find.text(l10nEn.deleteItemWorkouts), findsOneWidget);
      expect(find.text(l10nEn.deleteItemPlans), findsOneWidget);
      await tester.tap(find.byKey(const Key('delete_cancel')));
      await tester.tap(find.byKey(const Key('delete_confirm')));
      expect(calls, ['cancel', 'delete']);
    });

    testWidgets('"also erase this phone\'s workouts" is its own choice', (
      tester,
    ) async {
      bool? chosen;
      await tester.pumpApp(view(onEraseLocalChanged: (v) => chosen = v));
      await tester.tap(find.byKey(const Key('delete_erase_local')));
      expect(chosen, isTrue);
    });

    testWidgets('an owner must type the gym name exactly', (tester) async {
      var deleted = 0;
      await tester.pumpApp(
        view(ownedGymName: 'Iron House', onDelete: () => deleted++),
      );
      expect(find.text(l10nEn.deleteOwnerPrompt('Iron House')), findsOneWidget);

      await tester.scrollUntilVisible(
        find.byKey(const Key('delete_owner_name')),
        100,
      );
      final button = find.byKey(const Key('delete_confirm'));
      await tester.tap(button, warnIfMissed: false);
      expect(deleted, 0, reason: 'nothing typed yet');

      for (final wrong in ['iron house', 'Iron', 'Iron House 2', '<b>']) {
        await tester.enterText(
          find.byKey(const Key('delete_owner_name')),
          wrong,
        );
        await tester.pump();
        await tester.tap(button, warnIfMissed: false);
        expect(deleted, 0, reason: wrong);
      }

      await tester.enterText(
        find.byKey(const Key('delete_owner_name')),
        '  Iron House ',
      );
      await tester.pump();
      await tester.tap(button);
      expect(deleted, 1);
    });

    testWidgets('a person who owns no gym types nothing', (tester) async {
      await tester.pumpApp(view());
      expect(find.byKey(const Key('delete_owner_name')), findsNothing);
    });

    testWidgets('a sole owner is told what to do first', (tester) async {
      await tester.pumpApp(
        view(failure: const LastOwnerFailure(['Iron House', 'Peak'])),
      );
      expect(find.text(l10nEn.deleteLastOwnerTitle), findsOneWidget);
      expect(
        find.text(l10nEn.deleteLastOwnerBody('Iron House، Peak')),
        findsOneWidget,
      );
    });

    testWidgets('other failures show their message', (tester) async {
      await tester.pumpApp(view(failure: const NetworkFailure()));
      expect(find.text(l10nEn.errorNetwork), findsOneWidget);
    });

    testWidgets('while deleting nothing else can be tapped', (tester) async {
      var calls = 0;
      await tester.pumpApp(
        view(
          busy: true,
          onDelete: () => calls++,
          onCancel: () => calls++,
          onEraseLocalChanged: (_) => calls++,
        ),
      );
      for (final key in [
        'delete_confirm',
        'delete_cancel',
        'delete_erase_local',
      ]) {
        await tester.tap(find.byKey(Key(key)), warnIfMissed: false);
      }
      expect(calls, 0);
    });

    testWidgets('meets accessibility guidelines', (tester) async {
      await tester.pumpApp(view(ownedGymName: 'Iron House'));
      await tester.expectAccessible();
    });
  });

  screensUiTests({
    'delete_account': view,
    'delete_account_erase_local': () => view(eraseLocal: true),
    'delete_account_owner': () => view(ownedGymName: 'Iron House'),
    'delete_account_last_owner': () => view(
      ownedGymName: 'Iron House',
      failure: const LastOwnerFailure(['Iron House']),
    ),
    'delete_account_error': () => view(failure: const NetworkFailure()),
    'delete_account_busy': () => view(busy: true),
  });
}
