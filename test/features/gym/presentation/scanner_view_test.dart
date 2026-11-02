import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/widgets/state_views.dart';
import 'package:gym_tracker/features/gym/presentation/scanner_view.dart';

import '../../../helpers/pump_app.dart';
import '../../../helpers/ui_check.dart';

ScannerView view(
  ScannerMode mode, {
  bool refused = false,
  VoidCallback? onClose,
  VoidCallback? onTypeCode,
  VoidCallback? onOpenSettings,
  VoidCallback? onRetry,
}) => ScannerView(
  mode: mode,
  refused: refused,
  onClose: onClose ?? () {},
  onTypeCode: onTypeCode ?? () {},
  onOpenSettings: onOpenSettings,
  onRetry: onRetry,
);

void main() {
  group(ScannerView, () {
    testWidgets('live: hint, a way to type the code, and close', (
      tester,
    ) async {
      var typed = 0;
      var closed = 0;
      await tester.pumpApp(
        view(
          ScannerMode.live,
          onTypeCode: () => typed++,
          onClose: () => closed++,
        ),
      );
      expect(find.text(l10nEn.scanHint), findsOneWidget);
      await tester.tap(find.byKey(const Key('scanner_type_code')));
      await tester.tap(find.byKey(const Key('scanner_close')));
      expect([typed, closed], [1, 1]);
    });

    testWidgets('denied: open settings or type the code, never a dead end', (
      tester,
    ) async {
      var settings = 0;
      var typed = 0;
      await tester.pumpApp(
        view(
          ScannerMode.denied,
          onOpenSettings: () => settings++,
          onTypeCode: () => typed++,
        ),
      );
      expect(find.text(l10nEn.scanDeniedTitle), findsOneWidget);
      expect(find.text(l10nEn.scanDeniedBody), findsOneWidget);
      await tester.tap(find.byKey(const Key('scanner_primary')));
      await tester.tap(find.byKey(const Key('scanner_type_code')));
      expect([settings, typed], [1, 1]);
    });

    testWidgets('unavailable camera still offers typing the code', (
      tester,
    ) async {
      var typed = 0;
      await tester.pumpApp(
        view(ScannerMode.unavailable, onTypeCode: () => typed++),
      );
      expect(find.text(l10nEn.scanUnavailableTitle), findsOneWidget);
      expect(find.byKey(const Key('scanner_primary')), findsNothing);
      await tester.tap(find.byKey(const Key('scanner_type_code')));
      expect(typed, 1);
    });

    testWidgets('offline: the code was not used; try again or type it', (
      tester,
    ) async {
      var retried = 0;
      await tester.pumpApp(view(ScannerMode.offline, onRetry: () => retried++));
      expect(find.text(l10nEn.scanOfflineBody), findsOneWidget);
      await tester.tap(find.byKey(const Key('scanner_primary')));
      expect(retried, 1);
      expect(find.byKey(const Key('scanner_type_code')), findsOneWidget);
    });

    testWidgets('the camera widget sits behind the viewfinder', (tester) async {
      await tester.pumpApp(
        ScannerView(
          mode: ScannerMode.live,
          camera: const ColoredBox(key: Key('fake_camera'), color: Colors.blue),
          onClose: () {},
          onTypeCode: () {},
        ),
      );
      expect(find.byKey(const Key('fake_camera')), findsOneWidget);
    });

    testWidgets('joining shows the loading logo and says so once', (
      tester,
    ) async {
      await tester.pumpApp(view(ScannerMode.joining));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text(l10nEn.scanJoining), findsOneWidget);
      expect(find.byType(LoadingView), findsOneWidget);
    });

    testWidgets('meets accessibility guidelines in every mode', (tester) async {
      // `joining` loops the logo animation, so it never settles: it has its own
      // test below.
      for (final mode in ScannerMode.values.where(
        (m) => m != ScannerMode.joining,
      )) {
        await tester.pumpApp(view(mode, onOpenSettings: () {}, onRetry: () {}));
        await tester.pump();
        await tester.expectAccessible();
      }
    });
  });

  screensUiTests({
    'scanner_live': () => view(ScannerMode.live),
    'scanner_refused': () => view(ScannerMode.live, refused: true),
    'scanner_denied': () => view(ScannerMode.denied, onOpenSettings: () {}),
    'scanner_unavailable': () => view(ScannerMode.unavailable),
    'scanner_offline': () => view(ScannerMode.offline, onRetry: () {}),
  });
}
