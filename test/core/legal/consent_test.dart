import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/core/legal/consent_gate.dart';
import 'package:gym_tracker/core/legal/consent_view.dart';
import 'package:gym_tracker/core/legal/legal.dart';
import 'package:gym_tracker/core/router/app_routes.dart';
import 'package:gym_tracker/core/theme/app_dimens.dart';
import 'package:gym_tracker/core/theme/app_theme.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/ui_check.dart';

class _MemoryStore implements ConsentStore {
  new([this.value]);

  String? value;

  @override
  String? accepted() => value;

  @override
  Future<void> accept(String version) async => value = version;
}

Widget view() => AppScaffold(
  body: Align(
    alignment: Alignment.bottomCenter,
    child: ConsentView(
      onAgree: () {},
      onOpenPrivacy: () {},
      onOpenTerms: () {},
      onOpenYouTubeTerms: () {},
      onOpenGooglePrivacy: () {},
    ),
  ),
);

void main() {
  group(ConsentGate, () {
    Future<void> pumpGate(
      WidgetTester tester,
      ConsentStore store, {
      String at = '/',
      List<Uri>? opened,
    }) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      final router = GoRouter(
        navigatorKey: navigatorKey,
        initialLocation: at,
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Text('home')),
          GoRoute(
            path: AppRoutes.welcome,
            builder: (context, _) => TextButton(
              onPressed: () => context.go('/'),
              child: const Text('welcome'),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        AppUi.testWrap(
          AppScreenScale(
            builder: (context) => MaterialApp.router(
              routerConfig: router,
              theme: AppTheme.light,
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              builder: (context, child) => ConsentGate(
                store: store,
                router: router,
                navigatorKey: navigatorKey,
                open: (url) async => opened?.add(url),
                child: child!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('not agreed yet: a sheet over the screen, once', (
      tester,
    ) async {
      final store = _MemoryStore();
      await pumpGate(tester, store);
      expect(find.text('home'), findsOneWidget);
      expect(find.byType(ConsentView), findsOneWidget);
      await tester.tap(find.byKey(const Key('consent_agree')));
      await tester.pumpAndSettle();
      expect(find.byType(ConsentView), findsNothing);
      expect(store.value, ConsentStore.current);
    });

    testWidgets("it can't be swiped, tapped or backed away", (tester) async {
      await pumpGate(tester, _MemoryStore());
      await tester.tapAt(const Offset(10, 10)); // the barrier
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ConsentView), findsOneWidget);
    });

    testWidgets('agreed to this version: nothing shows', (tester) async {
      await pumpGate(tester, _MemoryStore(ConsentStore.current));
      expect(find.byType(ConsentView), findsNothing);
    });

    for (final old in ['2026-01-01', '', "x'; drop --"]) {
      testWidgets('an older or hostile stored value ($old): asked again', (
        tester,
      ) async {
        await pumpGate(tester, _MemoryStore(old));
        expect(find.byType(ConsentView), findsOneWidget);
      });
    }

    testWidgets('on the welcome screen it waits (choosing agrees there)', (
      tester,
    ) async {
      final store = _MemoryStore();
      await pumpGate(tester, store, at: AppRoutes.welcome);
      expect(find.byType(ConsentView), findsNothing);
      // Left the welcome screen without agreeing: asked then.
      await tester.tap(find.text('welcome'));
      await tester.pumpAndSettle();
      expect(find.byType(ConsentView), findsOneWidget);
    });

    testWidgets('the four links open exactly these pages', (tester) async {
      final opened = <Uri>[];
      await pumpGate(tester, _MemoryStore(), opened: opened);
      for (final key in [
        'consent_privacy',
        'consent_terms',
        'consent_youtube_terms',
        'consent_google_privacy',
      ]) {
        await tester.tap(find.byKey(Key(key)));
      }
      expect(opened, [
        LegalLinks.privacy,
        LegalLinks.terms,
        LegalLinks.youTubeTerms,
        LegalLinks.googlePrivacy,
      ]);
      expect(
        LegalLinks.privacy.toString(),
        'https://azmm.pages.dev/privacy.html',
      );
      expect(
        LegalLinks.youTubeTerms.toString(),
        'https://www.youtube.com/t/terms',
      );
    });
  });

  test('acceptTerms records the current version once', () async {
    final store = _MemoryStore();
    await acceptTerms(store, via: 'welcome');
    expect(store.value, ConsentStore.current);
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
