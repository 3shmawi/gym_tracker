import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/features/gym/domain/entities/invite_code.dart';
import 'package:gym_tracker/features/gym/presentation/join_view.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';

void main() {
  Finder field() => find.descendant(
    of: find.byKey(const Key('join_code')),
    matching: find.byType(TextField),
  );

  Text message(WidgetTester tester) => tester.widget<Text>(
    find.descendant(
      of: find.byKey(const Key('join_message')),
      matching: find.byType(Text),
      matchRoot: true,
    ),
  );

  group(JoinView, () {
    testWidgets('typing fills the boxes; Join is on only for a full code', (
      tester,
    ) async {
      InviteCode? submitted;
      await tester.pumpApp(JoinView(onSubmit: (c) => submitted = c));

      final join = find.byKey(const Key('join_submit'));
      await tester.enterText(field(), 'k7m');
      await tester.pump();
      expect(find.text('K'), findsOneWidget);
      await tester.tap(join, warnIfMissed: false);
      expect(submitted, isNull, reason: 'three characters are not a code');

      await tester.enterText(field(), 'k7m-2qx9');
      await tester.pump();
      expect(find.text('X'), findsOneWidget);
      expect(find.text('9'), findsNothing, reason: 'at most six characters');
      await tester.tap(join);
      expect(submitted, InviteCode.tryParse('K7M2QX'));
    });

    testWidgets('hostile typing and pasting only keeps valid characters', (
      tester,
    ) async {
      InviteCode? submitted;
      await tester.pumpApp(JoinView(onSubmit: (c) => submitted = c));
      for (final text in [
        '<script>alert(1)</script>',
        "'; drop table invites;--",
        '0O1IL',
        'ßſＡ',
        'A' * 5000,
      ]) {
        await tester.enterText(field(), text);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: text);
        final shown = tester.widget<TextField>(field()).controller!.text;
        expect(shown.length, lessThanOrEqualTo(6), reason: text);
        expect(InviteCode.clean(shown), shown, reason: text);
      }
      expect(submitted, isNull);
    });

    testWidgets('a link only fills the code: nothing is submitted', (
      tester,
    ) async {
      var submits = 0;
      await tester.pumpApp(
        JoinView(
          initialCode: 'k7m2qx',
          fromLink: true,
          onSubmit: (_) => submits++,
        ),
      );
      expect(find.text('K'), findsOneWidget);
      expect(message(tester).data, l10nEn.joinFromLink);
      await tester.pumpAndSettle();
      expect(submits, 0, reason: 'opening the screen must not join');

      await tester.tap(find.byKey(const Key('join_submit')));
      expect(submits, 1, reason: 'only the tap of the member joins');
    });

    testWidgets('editing a pre-filled code drops the link banner', (
      tester,
    ) async {
      await tester.pumpApp(
        JoinView(initialCode: 'K7M2QX', fromLink: true, onSubmit: (_) {}),
      );
      await tester.enterText(field(), 'K7M2Q');
      await tester.pump();
      expect(message(tester).data, l10nEn.joinHint);
    });

    testWidgets('an incomplete link says so and leaves the field empty', (
      tester,
    ) async {
      await tester.pumpApp(
        JoinView(linkIncomplete: true, fromLink: true, onSubmit: (_) {}),
      );
      expect(message(tester).data, l10nEn.joinLinkIncomplete);
      expect(tester.widget<TextField>(field()).controller!.text, isEmpty);
    });

    testWidgets('while joining is not built, Join stays off and says so', (
      tester,
    ) async {
      await tester.pumpApp(
        const JoinView(initialCode: 'K7M2QX', onSubmit: null),
      );
      expect(find.byKey(const Key('join_not_ready')), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('join_submit')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('meets accessibility guidelines', (tester) async {
      await tester.pumpApp(
        JoinView(initialCode: 'K7M2QX', fromLink: true, onSubmit: (_) {}),
      );
      await tester.expectAccessible();
    });
  });

  screensUiTests({
    'join_empty': () => JoinView(onSubmit: (_) {}),
    'join_from_link': () =>
        JoinView(initialCode: 'K7M2QX', fromLink: true, onSubmit: (_) {}),
    'join_link_incomplete': () =>
        JoinView(linkIncomplete: true, fromLink: true, onSubmit: (_) {}),
    'join_not_ready': () =>
        const JoinView(initialCode: 'K7M2QX', onSubmit: null),
  });
}
