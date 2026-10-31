import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/network/app_failure.dart';
import 'package:gym_tracker/core/widgets/offline_banner.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';

import '../../helpers/pump_app.dart';

void main() {
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
}
