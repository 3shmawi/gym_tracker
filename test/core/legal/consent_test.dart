import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/legal/consent_gate.dart';
import 'package:gym_tracker/core/legal/consent_view.dart';
import 'package:gym_tracker/core/legal/legal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/ui_check.dart';

class _MemoryStore implements ConsentStore {
  new([this.value]);

  String? value;

  @override
  String? accepted() => value;

  @override
  Future<void> accept(String version) async => value = version;
}

Widget view() => ConsentView(
  onAgree: () {},
  onOpenPrivacy: () {},
  onOpenTerms: () {},
  onOpenYouTubeTerms: () {},
  onOpenGooglePrivacy: () {},
);

void main() {
  group(ConsentGate, () {
    Widget gate(ConsentStore store, {List<Uri>? opened}) => ConsentGate(
      store: store,
      open: (url) async => opened?.add(url),
      child: const Text('the app'),
    );

    testWidgets('first launch: the app waits until the member agrees', (
      tester,
    ) async {
      final store = _MemoryStore();
      await tester.pumpApp(gate(store));
      expect(find.text('the app'), findsNothing);
      expect(find.text('Before you start'), findsOneWidget);
      await tester.tap(find.byKey(const Key('consent_agree')));
      await tester.pumpAndSettle();
      expect(find.text('the app'), findsOneWidget);
      expect(store.value, ConsentStore.current);
    });

    testWidgets('agreed to this version: straight to the app', (tester) async {
      await tester.pumpApp(gate(_MemoryStore(ConsentStore.current)));
      expect(find.text('the app'), findsOneWidget);
      expect(find.byType(ConsentView), findsNothing);
    });

    testWidgets('agreed to an older version, or a hostile value: asked again', (
      tester,
    ) async {
      for (final old in ['2026-01-01', '', "x'; drop --"]) {
        await tester.pumpApp(gate(_MemoryStore(old)));
        expect(find.byType(ConsentView), findsOneWidget, reason: old);
      }
    });

    testWidgets('the four links open exactly these pages', (tester) async {
      final opened = <Uri>[];
      await tester.pumpApp(gate(_MemoryStore(), opened: opened));
      for (final key in [
        'consent_privacy',
        'consent_terms',
        'consent_youtube_terms',
        'consent_google_privacy',
      ]) {
        await tester.tap(find.byKey(Key(key)));
      }
      expect(opened, [
        Uri.parse('https://azmm.pages.dev/privacy.html'),
        Uri.parse('https://azmm.pages.dev/terms.html'),
        Uri.parse('https://www.youtube.com/t/terms'),
        Uri.parse('https://www.google.com/policies/privacy'),
      ]);
    });
  });

  test('the phone copy: only a string counts', () async {
    SharedPreferences.setMockInitialValues({PrefsConsentStore.key: 42});
    final store = PrefsConsentStore(await SharedPreferences.getInstance());
    expect(store.accepted(), isNull);
    await store.accept(ConsentStore.current);
    expect(store.accepted(), ConsentStore.current);
  });

  screenUiTests('consent', view);
}
