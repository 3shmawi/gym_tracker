import 'dart:convert';

/// The page the headless web view loads to get a Turnstile token, and the
/// messages it sends back. Pure, so it is tested without a web view.
abstract final class TurnstilePage {
  /// A Turnstile site key: letters, digits, `_` and `-` only. Anything else
  /// is refused before it can reach the page's script.
  static final _key = RegExp(r'^[0-9A-Za-z_-]{10,64}$');

  static bool isValidSiteKey(String key) => _key.hasMatch(key);

  /// The only hosts the web view may open: the Turnstile script and its
  /// challenge frames. Everything else is blocked.
  static const allowedHost = 'challenges.cloudflare.com';
  static const channel = 'AzmTurnstile';

  /// Whether the web view may open [url]: the Turnstile host, blank frames,
  /// and the page itself.
  ///
  /// [baseUrl] is the address the page itself is loaded as
  /// (`loadHtmlString(..., baseUrl:)`). iOS reports that first load as a
  /// navigation to it, so exactly that page (`https://<host>/`, no other
  /// path, query or fragment) is allowed too; without it the page never
  /// loads and the join waits for the timeout.
  static bool allowsNavigation(String url, {String? baseUrl}) {
    if (url == 'about:blank' || url == 'about:srcdoc') return true;
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    if (uri.scheme == 'https' && uri.host == allowedHost) return true;
    final base = baseUrl == null ? null : Uri.tryParse(baseUrl);
    return base != null &&
        uri.scheme == 'https' &&
        base.scheme == 'https' &&
        uri.host == base.host &&
        uri.port == base.port &&
        uri.userInfo.isEmpty &&
        (uri.path == '' || uri.path == '/') &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  /// Renders the widget at once, shown only when Cloudflare needs the person
  /// (`interaction-only`), and reports the token, an error or a timeout to
  /// [channel]. The site key is validated, never trusted.
  static String html(String siteKey) {
    if (!isValidSiteKey(siteKey)) {
      throw ArgumentError.value(siteKey, 'siteKey', 'not a Turnstile site key');
    }
    return '''
<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<script src="https://$allowedHost/turnstile/v0/api.js?onload=azmReady&render=explicit" async defer></script>
</head><body style="margin:0">
<div id="w"></div>
<script>
function post(kind, value) {
  $channel.postMessage(JSON.stringify({k: kind, v: value || ''}));
}
function azmReady() {
  try {
    turnstile.render('#w', {
      sitekey: '$siteKey',
      appearance: 'interaction-only',
      callback: function (t) { post('token', t); },
      'error-callback': function (c) { post('error', String(c)); },
      'timeout-callback': function () { post('timeout'); },
      'expired-callback': function () { post('expired'); }
    });
  } catch (e) { post('error', 'render'); }
}
</script></body></html>''';
  }

  /// A message from the page: the token, or why there is none. Null for
  /// anything that is not exactly the page's own format.
  static TurnstileMessage? parse(String raw) {
    if (raw.length > 4096) return null;
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return null;
    }
    if (json is! Map || json.length != 2) return null;
    final kind = json['k'];
    final value = json['v'];
    if (kind is! String || value is! String) return null;
    switch (kind) {
      case 'token':
        return _token.hasMatch(value) ? TurnstileMessage.token(value) : null;
      case 'error':
        return const TurnstileMessage.failed();
      case 'timeout':
      case 'expired':
        return const TurnstileMessage.timedOut();
      default:
        return null;
    }
  }

  /// A token is long, URL-safe text.
  static final _token = RegExp(r'^[A-Za-z0-9._-]{10,2048}$');
}

class TurnstileMessage {
  const new token(this.value) : failed = false, timedOut = false;
  const new failed() : value = null, failed = true, timedOut = false;
  const new timedOut() : value = null, failed = false, timedOut = true;

  final String? value;
  final bool failed;
  final bool timedOut;
}
