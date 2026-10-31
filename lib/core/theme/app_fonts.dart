import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The app's fonts, chosen per app idea and bundled in assets/fonts (no
/// runtime download). Latin text uses [latin]; Arabic characters fall back
/// to [arabic] automatically, so mixed text renders correctly.
abstract final class AppFonts {
  static const latin = 'Inter';
  static const arabic = 'Cairo';

  /// Open Font License texts, shown on the app's licenses page.
  static const _licenseAssets = <String>[
    'assets/fonts/Inter/LICENSE.txt',
    'assets/fonts/Cairo/LICENSE.txt',
  ];

  static void registerLicenses() {
    if (_licenseAssets.isEmpty) return;
    LicenseRegistry.addLicense(() async* {
      for (final asset in _licenseAssets) {
        final text = await rootBundle.loadString(asset);
        yield LicenseEntryWithLineBreaks(const ['fonts'], text);
      }
    });
  }
}
