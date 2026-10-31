import 'package:flutter/services.dart';

/// The flavor the app was built with (`--flavor dev|staging|prod`).
/// Builds without a flavor are treated as [AppFlavor.prod].
enum AppFlavor {
  dev,
  staging,
  prod;

  static final AppFlavor current = AppFlavor.values.firstWhere(
    (flavor) => flavor.name == appFlavor,
    orElse: () => AppFlavor.prod,
  );

  bool get isProd => this == AppFlavor.prod;
}
