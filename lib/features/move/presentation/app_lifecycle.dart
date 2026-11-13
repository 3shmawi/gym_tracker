import 'package:flutter/widgets.dart';

/// The app is really off screen: the app switcher, another app, the lock
/// screen. Not [AppLifecycleState.inactive], which Android and iOS also
/// report while a system dialog (the camera permission!), the notification
/// shade or a call banner covers the app for a moment.
///
/// Releasing the camera on `inactive` cut the camera off in the middle of
/// its first start, behind the permission dialog, and left the round
/// waiting forever.
bool offScreen(AppLifecycleState state) =>
    state == AppLifecycleState.hidden ||
    state == AppLifecycleState.paused ||
    state == AppLifecycleState.detached;
