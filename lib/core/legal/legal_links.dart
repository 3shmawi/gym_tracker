import 'package:url_launcher/url_launcher.dart';

/// The app's legal pages, published from `website/` with the app. Null
/// until the website has an https address (then Settings hides the row).
abstract final class LegalLinks {
  static const _site = 'https://azmm.pages.dev';

  static Uri? get privacy => _page('privacy.html');
  static Uri? get terms => _page('terms.html');

  static Uri? _page(String file) =>
      _site.startsWith('https://') ? Uri.parse('$_site/$file') : null;
}

/// Opens one of the [LegalLinks] in the browser; false when nothing could.
Future<bool> openLegalPage(Uri url) =>
    launchUrl(url, mode: LaunchMode.externalApplication);
