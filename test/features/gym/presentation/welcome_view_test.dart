import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/legal/legal_links_row.dart';
import 'package:gym_tracker/features/gym/presentation/welcome_view.dart';
import 'package:gym_tracker/l10n/l10n.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';

void main() {
  group(WelcomeView, () {
    testWidgets('three ways forward, each calls its own callback', (
      tester,
    ) async {
      final calls = <String>[];
      await tester.pumpApp(
        WelcomeView(
          onJoin: () => calls.add('join'),
          onSolo: () => calls.add('solo'),
          onHaveCode: () => calls.add('code'),
        ),
      );
      expect(find.text(l10nEn.welcomeTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('welcome_join')));
      await tester.tap(find.byKey(const Key('welcome_solo')));
      await tester.tap(find.byKey(const Key('welcome_have_code')));
      expect(calls, ['join', 'solo', 'code']);
    });

    testWidgets('nothing is chosen for the person', (tester) async {
      final calls = <String>[];
      await tester.pumpApp(
        WelcomeView(
          onJoin: () => calls.add('join'),
          onSolo: () => calls.add('solo'),
          onHaveCode: () => calls.add('code'),
        ),
      );
      await tester.pump(const Duration(seconds: 5));
      expect(calls, isEmpty);
    });

    testWidgets('meets accessibility guidelines', (tester) async {
      await tester.pumpApp(
        WelcomeView(onJoin: () {}, onSolo: () {}, onHaveCode: () {}),
      );
      await tester.expectAccessible();
    });

    testWidgets('choosing how to start is agreeing: the line and links', (
      tester,
    ) async {
      final opened = <String>[];
      await tester.pumpApp(
        WelcomeView(
          onJoin: () {},
          onSolo: () {},
          onHaveCode: () {},
          legalLinks: legal(opened),
        ),
      );
      expect(find.text(l10nEn.consentByContinuing), findsOneWidget);
      for (final key in ['terms', 'privacy', 'youtube']) {
        await tester.ensureVisible(find.byKey(Key('welcome_$key')));
        await tester.tap(find.byKey(Key('welcome_$key')));
      }
      expect(opened, ['terms', 'privacy', 'youtube']);
    });

    testWidgets('has no back button: it is the first screen', (tester) async {
      await tester.pumpApp(
        WelcomeView(onJoin: () {}, onSolo: () {}, onHaveCode: () {}),
      );
      expect(find.byTooltip('Back'), findsNothing);
    });
  });

  screensUiTests({
    'welcome': () => Builder(
      builder: (context) => WelcomeView(
        onJoin: () {},
        onSolo: () {},
        onHaveCode: () {},
        legalLinks: [
          LegalLink('welcome_terms', context.l10n.legalTerms, () {}),
          LegalLink('welcome_privacy', context.l10n.legalPrivacy, () {}),
          LegalLink('welcome_youtube', context.l10n.legalYouTubeTerms, () {}),
        ],
      ),
    ),
  });
}

List<LegalLink> legal(List<String> opened) => [
  LegalLink('welcome_terms', 'Terms of Use', () => opened.add('terms')),
  LegalLink('welcome_privacy', 'Privacy Policy', () => opened.add('privacy')),
  LegalLink(
    'welcome_youtube',
    'YouTube Terms of Service',
    () => opened.add('youtube'),
  ),
];
