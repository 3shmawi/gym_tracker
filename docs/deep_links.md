# Deep links

Routing uses go_router; every route in `lib/core/router/app_routes.dart` is
also a deep link.

| Path | Screen |
|---|---|
| `/` | Next workout (home): the workout waiting for the member |
| `/workout` | The workout in progress; with none, an empty state with a way home |
| `/progress` | Progress: every exercise, first → latest weight |
| `/progress/<exerciseId>` | One exercise's history (unknown ids: "not in your plan") |
| `/plan` | Plan editor: the days in order (no plan: "Build your plan", an empty plan) |
| `/plan/<dayId>` | One plan day's exercises (unknown ids: "This day isn't in your plan") |
| `/plan/<dayId>/<exerciseId>` | An exercise's names and targets (unknown ids: "not in your plan") |
| `/settings` | Settings |

Plan links only open the editor: nothing in a link (query or path) can add,
change or delete anything. Ids are encoded by `AppRoutes.planDay` /
`planExercise`; crafted ids are covered in `test/security/deep_link_test.dart`.

## Custom scheme (works now)
Scheme `azm://`, registered in `AndroidManifest.xml` and `ios/Runner/Info.plist`
(`CFBundleURLTypes`, `FlutterDeepLinkingEnabled`). Every path above works:
`azm://settings` — test with:
```bash
adb shell am start -a android.intent.action.VIEW -d "azm://settings"
xcrun simctl openurl booted "azm://settings"
```

## https links (Universal Links / App Links)
Host: `azmm.pages.dev` (Cloudflare Pages, Git integration, production branch
`main`, output directory `website/`). **Only `/join/*` opens the app**; every
other https path stays in the browser.

| Path | Behaviour |
|---|---|
| `/join/<code>` | Opens the app on the home screen. Reserved for invites: the code is never read, nothing changes. |
| `/join` (no code) | Not claimed by the website; inside the app: not-found page |

How it is wired:
- `website/.well-known/apple-app-site-association` — `components`:
  `/join/*`, appIDs `9RA43G2P63.com.mohager.azm` and `…azm.stg`.
- `website/.well-known/assetlinks.json` — packages `com.mohager.azm` and
  `com.mohager.azm.stg` with the Play app-signing SHA-256.
- `website/_headers` — serves both files as `application/json` (the AASA file
  has no extension, Pages would send `application/octet-stream`). Both files
  must answer 200 directly, with no redirect.
- iOS: `ios/Runner/Runner.entitlements` (`applinks:azmm.pages.dev`), set as
  `CODE_SIGN_ENTITLEMENTS` for every Runner configuration (both flavors).
- Android: intent filter with `android:autoVerify="true"`, scheme `https`,
  host `azmm.pages.dev`, `android:pathPrefix="/join/"`.
- Guarded by `test/security/well_known_test.dart` and
  `test/security/platform_config_test.dart`.

Manual store steps: `docs/release.md` → "Universal Links / App Links".

Test:
```bash
curl -sI https://azmm.pages.dev/.well-known/apple-app-site-association   # 200, application/json
adb shell pm get-app-links com.mohager.azm                                 # azmm.pages.dev: verified
xcrun simctl openurl booted "https://azmm.pages.dev/join/abc"
```
Docs checked 2026-11-02: Android "Verify Android App Links" (read in full: the
system fetches `/.well-known/assetlinks.json` per host; on Android 15+ changes
can take up to 7 days to reach devices, on 14 and lower they are read at
install/update). Apple's Associated Domains / AASA pages are JavaScript-only
and came back as titles from this session, and `developers.cloudflare.com` is
blocked in it, so those two rest on Apple's documented rules (HTTPS, status
200 without redirects, `application/json`, `components` format, CDN cache)
plus a check of the live site's headers. Re-read them when you next touch this.
