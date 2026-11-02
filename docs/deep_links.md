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
| `/welcome` | "How do you want to start?" (join a gym / train alone). Behind the `gym_join` flag |
| `/join/scan` | The QR scanner. Reads nothing from its address. Behind the flag |
| `/join/joined` | "Welcome to <gym>" right after a code was accepted; opened any other way it goes home. Behind the flag |
| `/profile` | My account. **Signed-in people only**: signed out → `/welcome` (flag off → home) |
| `/profile/delete` | Delete account. Signed-in only, same redirect. A link never deletes: only the button does |

Gym account links (`/welcome`, `/join/scan`, `/join/joined`, `/profile`,
`/profile/delete`) only open screens; a query or fragment changes nothing
(`test/security/deep_link_test.dart` → "gym account screens"). `/join/scan` and
`/join/joined` come before `/join/<code>`, and paths are case sensitive, so
`/join/SCAN` is only a wrong code. There is no `/gym` route: the switcher is a
sheet.

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
| `/join/<code>` | The enter-code screen with the code filled in. A link **never joins**: the member taps Join. A code that is not 6 characters of `A-H J K M N P-Z 2-9` (any case) shows an empty field and "this link has no valid code". |
| `/join` (no code) | The same screen, empty (opened by `azm://join` from the web page when it has no code). A query (`?c=…`) is ignored |
| `/join/<code>/…`, `/joinx/…` | Not found |
| scanned QR | Not a link: the in-app scanner takes `https://azmm.pages.dev/join/<code>`, `azm://join/<code>` or the bare code, nothing else (`InviteCode.fromScan`), and joins at once |

The whole `/join` family is behind the `gym_join` feature flag (PostHog,
`Flags.gymJoin`): **off, every `/join…` link opens the home screen**, as before
gym accounts. The flag goes on when joining works end to end and Turnstile
is set up (`docs/release.md` → "Gym accounts in the app").

The same links work as `azm://join/<code>` (custom scheme: Flutter maps the
host to the first path segment, like `azm://settings`).

**When the app is not installed** (or the link opened in an in-app browser),
https://azmm.pages.dev/join/<code> is a web page: `website/join.html` (served for
every `/join/*` by `website/_redirects`, a 200 rewrite). It reads the code from
the *path* only (never `?c=`), validates it with `^[A-HJKMNP-Z2-9]{6}$`, shows
it as text (`textContent`), and offers "Open in Azm" (`azm://join/<code>`), the
store button for the platform, and a copy button. No script means no code on
screen, but the buttons and both languages still work. It never calls a
backend and has no trackers (CSP `connect-src 'none'`, fonts served from the
same site). Design: boards 8a/8b of the gym accounts design.

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
xcrun simctl openurl booted "https://azmm.pages.dev/join/K7M2QX"
xcrun simctl openurl booted "azm://join/K7M2QX"
```
Docs checked 2026-11-02: Android "Verify Android App Links" (read in full: the
system fetches `/.well-known/assetlinks.json` per host; on Android 15+ changes
can take up to 7 days to reach devices, on 14 and lower they are read at
install/update). Apple's Associated Domains / AASA pages are JavaScript-only
and came back as titles from this session, and `developers.cloudflare.com` is
blocked in it, so those two rest on Apple's documented rules (HTTPS, status
200 without redirects, `application/json`, `components` format, CDN cache)
plus a check of the live site's headers. Re-read them when you next touch this.
