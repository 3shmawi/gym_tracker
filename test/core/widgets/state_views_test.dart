import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/ui/app_ui.dart';
import 'package:gym_tracker/core/widgets/offline_banner.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';

import '../../helpers/pump_app.dart';
import '../../helpers/ui_check.dart';

/// Loading screens loop forever; screenshots and layout checks need a
/// still frame, so they run with Reduce Motion (the static logo).
Widget _still(Widget child) => Builder(
  builder: (context) => MediaQuery(
    data: MediaQuery.of(context).copyWith(disableAnimations: true),
    child: child,
  ),
);

void main() {
  group(LoadingView, () {
    testWidgets('loops the logo animation with one label, no text', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await tester.pumpApp(const Scaffold(body: LoadingView()));
      final logo = tester.widget<AzmLogoAnimation>(
        find.byType(AzmLogoAnimation),
      );
      expect(logo.loop, isTrue);
      expect(find.bySemanticsLabel(l10nEn.loading), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.descendant(
          of: find.byType(LoadingView),
          matching: find.byType(RichText),
        ),
        findsNothing,
      );
      await tester.pump(const Duration(seconds: 3));
      expect(tester.hasRunningAnimations, isTrue);
      semantics.dispose();
    });

    testWidgets('sizes: inline < card < screen', (tester) async {
      double sideOf(LoadingSize size) {
        return tester.getSize(find.byType(AzmLogoAnimation)).width;
      }

      final sides = <double>[];
      for (final size in LoadingSize.values) {
        await tester.pumpApp(Scaffold(body: LoadingView(size: size)));
        sides.add(sideOf(size));
      }
      expect(sides, [48, 96, 166]);
    });

    testWidgets('Reduce Motion: the static logo, no motion', (tester) async {
      await tester.pumpApp(_still(const Scaffold(body: LoadingView())));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      await tester.expectAccessible();
    });
  });

  group(ErrorView, () {
    testWidgets('shows a friendly message and retries', (tester) async {
      var retried = false;
      await tester.pumpApp(
        Scaffold(
          body: ErrorView(
            failure: const NetworkFailure(),
            onRetry: () => retried = true,
          ),
        ),
      );

      expect(find.text(l10nEn.errorNetwork), findsOneWidget);
      await tester.tap(find.text(l10nEn.retry));
      expect(retried, isTrue);
      await tester.expectAccessible();
    });

    testWidgets('never shows technical details', (tester) async {
      await tester.pumpApp(
        Scaffold(
          body: ErrorView(failure: UnknownFailure(StateError('db password'))),
        ),
      );
      expect(find.textContaining('db password'), findsNothing);
      expect(find.text(l10nEn.errorUnknown), findsOneWidget);
    });
  });

  testWidgets('EmptyView shows its message', (tester) async {
    await tester.pumpApp(const Scaffold(body: EmptyView(message: 'Nothing')));
    expect(find.text('Nothing'), findsOneWidget);
  });

  group(OfflineBanner, () {
    testWidgets('appears when offline and hides when back online', (
      tester,
    ) async {
      final online = StreamController<bool>();
      addTearDown(online.close);
      await tester.pumpApp(
        OfflineBanner(
          onlineChanges: online.stream,
          child: const Scaffold(body: Text('content')),
        ),
      );

      expect(find.text(l10nEn.offlineBanner), findsNothing);

      online.add(false);
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.offlineBanner), findsOneWidget);

      online.add(true);
      await tester.pumpAndSettle();
      expect(find.text(l10nEn.offlineBanner), findsNothing);
    });
  });

  screensUiTests({
    'loading_view_screen': () => _still(const Scaffold(body: LoadingView())),
    'loading_view_card': () => _still(
      const Scaffold(
        body: Padding(
          padding: EdgeInsets.all(24),
          child: Card(
            child: SizedBox(
              height: 160,
              child: LoadingView(size: LoadingSize.card),
            ),
          ),
        ),
      ),
    ),
    'loading_view_inline': () => _still(
      const Scaffold(
        body: Center(
          child: SizedBox(
            height: 64,
            child: LoadingView(size: LoadingSize.inline),
          ),
        ),
      ),
    ),
    'error_view': () => Scaffold(
      body: ErrorView(failure: const NetworkFailure(), onRetry: () {}),
    ),
    'empty_view': () =>
        const Scaffold(body: EmptyView(message: 'Nothing here yet')),
  });
}
