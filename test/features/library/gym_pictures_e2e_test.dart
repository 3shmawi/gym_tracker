import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/flows/gym_pictures_flow.dart';

/// The gym pictures demo flow, without a device (the same steps as the
/// integration test).
void main() {
  testWidgets("the gym's pictures: frames, swipe, offline from the cache", (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1125, 2436)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await gymPicturesFlow(tester);
  });
}
