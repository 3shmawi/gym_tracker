import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/core/ui/app_toast.dart';

import '../../helpers/pump_app.dart';

void main() {
  Future<OverlayState> overlayOf(WidgetTester tester) async {
    await tester.pumpApp(
      Overlay(
        initialEntries: [OverlayEntry(builder: (_) => const SizedBox.expand())],
      ),
    );
    return tester.state<OverlayState>(find.byType(Overlay).last);
  }

  testWidgets('shows a message, reads it out, and goes away by itself', (
    tester,
  ) async {
    final overlay = await overlayOf(tester);
    AppToast.show(
      'Your captain updated your plan',
      direction: TextDirection.ltr,
      overlay: overlay,
      lasts: const Duration(seconds: 2),
    );
    await tester.pump();
    expect(find.text('Your captain updated your plan'), findsOneWidget);
    final semantics = tester.getSemantics(find.byKey(const Key('app_toast')));
    expect(semantics.label, contains('Your captain updated your plan'));
    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const Key('app_toast')), findsNothing);
  });

  testWidgets('a new message replaces the old one; Arabic is RTL', (
    tester,
  ) async {
    final overlay = await overlayOf(tester);
    AppToast.show('one', direction: TextDirection.ltr, overlay: overlay);
    AppToast.show(
      'الكابتن حدّث خطتك',
      direction: TextDirection.rtl,
      overlay: overlay,
    );
    await tester.pump();
    expect(find.text('one'), findsNothing);
    expect(find.text('الكابتن حدّث خطتك'), findsOneWidget);
    final direction = tester
        .widget<Directionality>(
          find
              .ancestor(
                of: find.text('الكابتن حدّث خطتك'),
                matching: find.byType(Directionality),
              )
              .first,
        )
        .textDirection;
    expect(direction, TextDirection.rtl);
    AppToast.dismiss();
    await tester.pump();
    expect(find.byKey(const Key('app_toast')), findsNothing);
  });

  testWidgets('it never blocks a tap underneath', (tester) async {
    var taps = 0;
    await tester.pumpApp(
      Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (_) => Align(
              alignment: Alignment.topCenter,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => taps++,
                child: const SizedBox(
                  key: Key('under'),
                  width: 200,
                  height: 80,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    final overlay = tester.state<OverlayState>(find.byType(Overlay).last);
    AppToast.show('x', direction: TextDirection.ltr, overlay: overlay);
    await tester.pump();
    await tester.tapAt(tester.getCenter(find.byKey(const Key('under'))));
    expect(taps, 1);
    AppToast.dismiss();
    await tester.pump();
  });
}
