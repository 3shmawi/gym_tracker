import 'dart:async';

import 'package:flutter/foundation.dart';

/// Tells the router to run its redirects again when something outside it
/// changes — here, the sign-in session — so a screen that needs an account
/// is left the moment the session ends (sign out, revoked, deleted).
class RouterRefresh extends ChangeNotifier {
  StreamSubscription<Object?>? _subscription;

  /// Follows [changes]; replaces an earlier source.
  void attach(Stream<Object?> changes) {
    unawaited(_subscription?.cancel());
    _subscription = changes.listen((_) => notifyListeners());
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

/// The router's refresh source (`appRouter.refreshListenable`).
final routerRefresh = RouterRefresh();
