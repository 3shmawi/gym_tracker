import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test/helpers/gym_pictures_app.dart';
import '../helpers/demo.dart';

/// The gym's pictures on the exercise screen: open an exercise, watch the
/// two frames of the move, swipe through four pictures of another, go
/// offline and open it again (the pictures come from the phone's cache).
/// Shared by the device demo (integration_test/app_test.dart) and the
/// device-free run (test/features/library/gym_pictures_e2e_test.dart).
Future<void> gymPicturesFlow(WidgetTester tester) async {
  final cloud = FakePictureCloud();
  await pumpGymPicturesApp(tester, cloud);
  await beat(tester, 1200);

  Future<void> settleShort([int ms = 600]) async {
    await tester.pump();
    await tester.pump(Duration(milliseconds: ms));
  }

  // The library: the gym's covers on its rows.
  // The gym's choice arrives from the phone's copy a frame later.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(find.text('Pictures from your gym'), findsWidgets);
  await tester.tap(find.byKey(const Key('library_row_flat_db_press')));
  await settleShort();
  await beat(tester, 1500);

  // Two frames of one move: it plays by itself, the button pauses it.
  expect(find.byKey(const Key('gym_pictures_toggle')), findsOneWidget);
  // Wait for the second frame in small steps (a simulator under load
  // can be slow to start the timer).
  for (var i = 0; i < 24; i++) {
    await tester.pump(const Duration(milliseconds: 500));
    if (find.text('\u20662 / 2\u2069').evaluate().isNotEmpty) break;
  }
  expect(find.text('\u20662 / 2\u2069'), findsOneWidget);
  await beat(tester, 2000);
  await tester.tap(find.byKey(const Key('gym_pictures_toggle')));
  await settleShort();
  await beat(tester, 1200);

  // Back, then an exercise with four pictures: swipe through them.
  await tester.tap(find.byTooltip('Back').hitTestable().first);
  await settleShort();
  await beat(tester);
  await tester.tap(find.byKey(const Key('library_row_incline_machine_press')));
  await settleShort();
  await beat(tester, 1200);
  expect(find.text('\u20661 / 4\u2069'), findsOneWidget);
  for (var i = 0; i < 2; i++) {
    await tester.drag(
      find.byKey(const Key('gym_pictures_pages')),
      Offset(
        Directionality.of(
                  tester.element(find.byKey(const Key('gym_pictures_pages'))),
                ) ==
                TextDirection.rtl
            ? 250
            : -250,
        0,
      ),
    );
    await settleShort();
    await beat(tester, 1000);
  }
  expect(find.text('\u20663 / 4\u2069'), findsOneWidget);
  final downloads = cloud.downloads;

  // Offline: the same exercise opens with the pictures already on the phone.
  cloud.online = false;
  await tester.tap(find.byTooltip('Back').hitTestable().first);
  await settleShort();
  await beat(tester);
  await tester.tap(find.byKey(const Key('library_row_incline_machine_press')));
  await settleShort();
  await beat(tester, 1500);
  expect(find.text('\u20661 / 4\u2069'), findsOneWidget);
  expect(cloud.downloads, downloads, reason: 'nothing downloaded offline');
}
