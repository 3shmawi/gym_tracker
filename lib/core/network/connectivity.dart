import 'package:connectivity_plus/connectivity_plus.dart';

/// Online/offline state of the device (true = has a network connection).
/// Having a connection doesn't guarantee the internet works — requests still
/// go through `guard` and can fail with a `NetworkFailure`.
abstract final class ConnectivityStatus {
  static Stream<bool> get onlineChanges async* {
    final connectivity = Connectivity();
    yield _isOnline(await connectivity.checkConnectivity());
    yield* connectivity.onConnectivityChanged.map(_isOnline).distinct();
  }

  static bool _isOnline(List<ConnectivityResult> results) =>
      results.any((result) => result != ConnectivityResult.none);
}
