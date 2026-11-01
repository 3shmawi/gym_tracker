# Deep links

Routing uses go_router; every route in `lib/core/router/app_routes.dart` is
also a deep link.

| Path | Screen |
|---|---|
| `/` | Next workout (home): the workout waiting for the member |
| `/workout` | The workout in progress; with none, an empty state with a way home |
| `/settings` | Settings |

## Custom scheme (works now)
Registered in `AndroidManifest.xml` and `ios/Runner/Info.plist`
(`CFBundleURLTypes`, `FlutterDeepLinkingEnabled`).
`gymtracker://settings` — test with:
```bash
adb shell am start -a android.intent.action.VIEW -d "gymtracker://settings"
xcrun simctl openurl booted "gymtracker://settings"
```

## https links (App Links / Universal Links)
Host: `example.com`. Needs, once:
1. The website served from that domain (root), including
   `website/.well-known/assetlinks.json` and
   `website/.well-known/apple-app-site-association`.
2. `assetlinks.json`: replace the SHA-256 with Play Console → Setup →
   App signing → "App signing key certificate" fingerprint.
3. `apple-app-site-association`: check the Team ID (`9RA43G2P63`).
4. Apple Developer → Identifiers → `com.mohager.azm` → enable
   **Associated Domains** (then CI regenerates the profile).

If no domain was chosen at creation, add later: intent filter in
`AndroidManifest.xml` (`android:autoVerify="true"`, scheme https) and
`ios/Runner/Runner.entitlements` with `applinks:<domain>`.
