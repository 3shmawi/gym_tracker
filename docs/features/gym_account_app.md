# Feature: gym accounts — the app (join, switch, profile)

> Step 3 of the delivery plan in [`../decisions/gym_accounts.md`](../decisions/gym_accounts.md) §13.
> Builds on the backend ([`gym_accounts_backend.md`](gym_accounts_backend.md)) and
> the join page + enter-code screen ([`gym_join.md`](gym_join.md)). Everything
> here is behind the **`gym_join`** flag (PostHog, off by default): off, the
> app behaves exactly as before and every new path opens home.

## What it does
- **First screen** (`/welcome`, design board 1, last phone): "How do you want to
  start?" — *Join your gym* / *Train on my own* / "I have a code". Asked once,
  and never to someone who already has a plan or an account. No account is made
  by any of the three: the account is made only when a code is redeemed.
- **Scanner** (`/join/scan`, boards 2a/2b): the camera reads the QR and joins at
  once (the person deliberately scanned). It accepts only
  `https://azmm.pages.dev/join/<code>`, `azm://join/<code>` or the bare code
  (`InviteCode.fromScan`); anything else is "invalid" and is never sent.
  States: live, camera denied, no camera, joining, offline, and sheets for
  invalid / expired (also revoked) / already used / not usable by this account /
  too many tries. Every dead end offers "Type the code instead".
- **Enter code** (`/join`, `/join/<code>`, board 3): the screen from #21, now
  wired. A link only pre-fills it. A wrong code is shown in the field (red
  boxes); the other reasons open the same sheets as the scanner.
- **Redeem**: if there is no session, `signInAnonymously()` (with the
  `captchaToken` seam, `null` until Turnstile is set up), then the
  `redeem_invite` Edge Function with `{code, install_id}`. The install id is a
  random v4 UUID in secure storage. A stored anonymous session the server no
  longer knows is replaced once; a permanent session never is.
- **Joined** (`/join/joined`, board 3): the gym's initials tile, "Welcome to
  <gym>", what a trainee may change (three permissions) and one line about
  privacy → *Start training* → Today.
- **Workspaces** (board 4): Solo or one active gym. A sheet "Where are you
  training?" (home bar button, profile). Ended memberships are listed below:
  *Read only* or *Locked* by the gym's setting; neither can be opened to log.
  A membership that ended, or a session that is gone → back to solo.
- **My account** (`/profile`, board 4): who you are, your gyms, *Change where you
  train*, **Sign out** (confirm dialog; one-way for anonymous accounts), **Add
  email** ("Secure your account": `updateUser(email)`, the account keeps its id,
  memberships and history) and **Delete account** (`/profile/delete`).
- **Delete account** (board 4): what is lost, "also delete this phone's
  workouts" (off by default), an owner types the gym name, `delete-account
  {confirm:"delete"}`; `409 last_owner` says which gyms to hand over first.
- **Solo data → account** (PR C, board 3 last phone): right after *Joined*, if the
  phone has workouts or a plan and the person has not answered, a sheet asks
  once: **Keep my solo data** (default), **Add my solo history to my account**,
  **Decide later**. *Keep* sends nothing and is never asked again. *Add* copies
  the workouts and the plan to the account (below). *Later* is asked again at the
  next join, and *My account* always has a row for it until it is done.
- **Settings** gets a *Gym* row: *My account* when signed in, *Join your gym*
  when not.

## Design
Copied from the approved board (`docs/design.md`): sizes, radii, colors, spacing
from `gym.css` / `extra.css`. New shared pieces in `lib/core/ui/app_gym_controls.dart`
(`AppLogoTile`, `AppOrb`, `AppListRow`, `AppRadioMark`, `AppBanner`,
`AppSectionLabel`, `AppViewfinder`, `AppCameraBackdrop`, `AppChoiceCard`),
`AppDangerButton(style:)` (tinted / outlined / solid) and `AppTextField`
(`keyboardType`, `autofillHints`). Tokens: `AppColors.gymBlue*`, `gymAmber*`,
`camera*`.

Deviations from the board, on purpose:
- The switcher is a **sheet** (as drawn), not a `/gym` route (decision doc §7
  said route). Nothing deep-links to it.
- *Delete my account* in dark mode uses the dark brand ink on the red fill: the
  board's white on `#F87171` is 2.8:1, under the 3:1 large-text minimum.
- Buttons keep the app's 60-px height (the board draws 52 for secondary ones).
- Pages 1–3 of the board's onboarding are described as "existing", but the app
  has no such pages: only the choose-your-path screen is built.
- No captain's name on *Joined* or in the switcher: a trainee cannot read
  anyone else's membership row (RLS), and `redeem_invite` does not return it.
  Showing it needs a backend addition (a `captain_name` on the gym answer).
- **Gym logos** (behind `gym_logos`, spec
  [`../designs/gym_logo.md`](../designs/gym_logo.md)): the logo the owner
  uploads in the dashboard replaces the letters on the gym's tile in the
  profile, the workspace switcher and *Joined*. The letters stay underneath:
  they show while the logo loads, when there is none, and if it can't be
  shown (the owner's fallback). Ended gyms keep their letters. See "Gym logos"
  below.

## Architecture (layered)
| Layer | What | Where |
|---|---|---|
| domain | `Gym`, `Membership`, `JoinedGym`, `GymRole`, `GymPermissions`, `Workspace`, `AccountSession`, `InviteCode.fromScan`; interfaces `GymRepository`, `AccountRepository`, `GymLocalRepository`, `InstallIdStore`; use cases `RedeemInvite`, `RefreshMemberships`, `LoadGymSnapshot`, `SwitchWorkspace`, `SignOut`, `DeleteAccount`, `HandleSessionEnded` | `lib/features/gym/domain/` |
| data | `SupabaseGymRepository` (sign-in + `redeem_invite` + memberships), `SupabaseAccountRepository`, `PrefsGymLocalRepository`, `SecureLocalStorage` (the Supabase session in Keychain/Keystore), `SecureInstallIdStore`, `FlutterSecretStore` | `lib/features/gym/data/` |
| presentation | `*_view.dart` (pure UI) + `*_page.dart` (wires state): welcome, scanner (+ `scanner_camera.dart`), join, joined, workspace sheet, profile, delete account; Riverpod `gymControllerProvider`, `accountSessionProvider`, `joinControllerProvider`, `accountActionsProvider` | `lib/features/gym/presentation/` |
| wiring | `Dependencies.gymRepository / accountRepository / gymLocalRepository`, `Backend.init` (secure session storage), `routerRefresh` | `lib/core/` |

Repositories never throw: `guard()` → `Result`. New failures: `InviteFailure`
(`invalid`, `expired`, `used`, `conflict`, `throttled`) and `LastOwnerFailure`
(gym names) in `app_failure.dart`, with messages in both ARB files;
`FunctionsFetchException` and `AuthRetryableFetchException` are network
failures.

### How the session is kept
`Supabase.initialize(authOptions: FlutterAuthClientOptions(localStorage:
SecureLocalStorage(...)))`. The default storage is `shared_preferences` (plain
text on Android). iOS items use `first_unlock_this_device` (readable for the
background refresh, never copied by a backup). The iOS Keychain **survives an
uninstall**, so on a fresh install (no shared preferences marker,
`Backend.installMarkerKey`) an old session is dropped: a reinstall is a new
phone for the server (decision doc §12). A store that cannot be read means "no
session", never a crash.

### Protected routes
`/profile` and `/profile/delete` redirect signed-out people to `/welcome` (flag
off: home). `routerRefresh` re-runs the redirects when the session starts or
ends, so a screen is left the moment the session is revoked. `/join/joined`
without a join goes home. The router itself never joins, signs out or deletes
(`test/security/gym_account_app_test.dart`).

### Workspaces today
The active workspace is stored on the phone (`gym:<membership id>` or `solo`),
and refreshed from the server when the app opens while signed in. In a gym
workspace the plan comes from the gym, the editor follows the membership's
rights, and finished workouts are uploaded (PR D: see "In a gym" in
`workout.md`). Opening an ended gym's readable history is not built.

## Solo data import (PR C)
`ImportSoloData` (`domain/usecases/import_solo_data.dart`) → RPC
`import_solo_data(p_sessions, p_plan)` (migration 0009).
- **What is sent:** the phone's finished workouts (≤ 200) that the server would
  accept, once each, oldest first, in chunks of **50**; the plan with the first
  call. `client_id` = `sha256(day_id|finished_at|sets)` (hex): `finished_at` is UTC
  ISO-8601, `sets` the JSON of `[{exercise, weight, reps}]` in logged order, so a
  workout always gets the same id. Workouts the server would refuse (finish time
  before 2020 or more than a day ahead, a bad id, > 500 sets, > 64 KB) are
  filtered on the phone first so they cannot sink a chunk of 50; they stay on the
  phone and are not counted.
- **Idempotent and resumable:** the server skips a `client_id` it already has. A
  run always starts from the first workout, so no stale cursor can skip one; after
  any failure (offline, dropped answer, app killed) the status stays `copying` and
  *Retry*, or the *My account* row, runs it again. `nextIndex` is only the progress line.
- **Nothing is lost:** the phone's workouts, plan, level and draft are never
  touched; the copy is `done` only when the server's `solo_total` covers every
  workout sent. (The "delete the local copy after the user confirms or after 30
  days" step of decision §10 is **not built**: nothing is ever deleted
  automatically; *Delete account → also erase this phone's workouts* is the one
  way, and it is the person's choice.)
- **Solo mode works signed out:** nothing here runs without an account, and the
  question only appears after joining.
- Sessions on the server stay *solo* (`gym_id` null): no captain sees them.

Tests: `solo_import_test.dart` (ids, the server's rules, chunks, a plan with no
workouts, a lost answer, a lying server, and **40 random histories with random
interruptions**: the server ends with exactly the valid workouts, never a chunk
it refuses, the phone keeps everything, a second run changes nothing),
`solo_import_data_test.dart`, `solo_import_sheet_test.dart` (+ `screensUiTests`),
`solo_import_flows_test.dart`.

## Turnstile
`TurnstileCaptcha` (`lib/core/captcha/`, `webview_flutter` 4.14.1 read on
pub.dev 2026-11-02; Cloudflare's own docs were not reachable from the build
environment; `cloudflare_turnstile` was tried first and dropped: its
`flutter_inappwebview` 1.1.3 (last stable 2024) breaks the Android build with the
current Gradle) gets a token from a 1-pixel web view (`appearance:
'interaction-only'`; it cannot show a challenge) and feeds
`SupabaseGymRepository.captchaToken`. Off (no token) when `TURNSTILE_SITE_KEY` is
empty. Failures: no answer in 20 s → `TimeoutFailure`, retryable widget error →
`NetworkFailure`, refusal → `UnknownFailure`; the join then shows its normal
"couldn't join" / offline sheet.

## Gym logos
- **Following changes.** The memberships (name, colour, logo) are now asked
  for again on resume and when the network returns (`GymSyncHost._run` →
  `GymController.refresh`, then the logo sync), not only on a cold start.
  Refreshes that come together share one request.
- **Knowing a logo changed.** `gyms.logo_updated_at` (migration 0023) is set
  by the database on every write of `logo_path`, so a logo replaced at the
  same path has a new version. `Gym.logoPath` / `logoVersion` are **not** in
  `Gym ==`, so a new logo never restarts the workout, the plan or the
  pictures.
- **Download.** `SyncGymLogos` (domain) runs after each refresh, one gym at a
  time: logos of active memberships only, at most 10.
  - `SupabaseGymLogoRepository` downloads from the private `gym-logos` bucket
    with the member's session, using the version as a cache nonce.
  - `GymLogoCheck` reads the size from the PNG/JPEG header **before any
    decode**, and refuses: empty, over 512 KB, not PNG/JPEG, broken, animated,
    or smaller than 16 or larger than 2048 px a side.
- **On the phone.** `FileGymLogoStore` writes
  `<support dir>/gym_logos/<gym id>-<version>.img`, with an index in
  `gym.logos`.
  - The order is temp file, rename, index, then deleting the old file.
  - The version is in the file name, so Flutter's image cache never shows an
    old logo.
  - It is cleared with the rest of the gym state (sign-out, a session ended,
    the account deleted).
- **Showing it.**
  - Pages pass `gymLogoImagesProvider` (gym id → image) to their views.
  - `AppLogoTile(image:)` decodes at the tile's size only (`ResizeImage`) and
    fades the logo in over 200 ms (none with Reduce Motion).
  - It draws a thin `keyFill` edge, so a white logo still reads as a tile.
- **The letters take the gym's colour** (behind `gym_brand_colours`, the
  owner's ask on 2026-11-14). When the owner chose a colour, the letters
  tile is filled with it through `BrandColors.fromSeed`, the rule the
  theme uses. The letters are white or dark, whichever keeps 4.5:1. With
  no colour it is the design's blue or amber gradient, as before. Pages
  pass `gymTileColorsProvider` (active gyms only) to the views.
- **Flag `gym_logos`** (off): with it off nothing downloads, and the tiles
  show letters even if a logo is kept.

## Analytics (no personal data)
| Event | Properties |
|---|---|
| `gym_join_started` | `via`: `scan` \| `link` \| `code` |
| `gym_joined` | `via` |
| `gym_join_failed` | `reason`: `invalid` \| `expired` \| `used` \| `conflict` \| `throttled` \| `offline` \| `error` |
| `gym_switched` | `to`: `solo` \| `gym` |
| `account_signed_out`, `account_deleted` | — |
| `solo_import_started`, `solo_import_done` | — |
| `solo_import_failed` | `reason` (same words as `gym_join_failed`) |

Gym logos send no events; the logo's path or gym id is never in an event
or an error report (a refused logo reports only the reason).

Never a code, a name, an id or an email (`gym_account_app_test.dart` checks the
event names and property keys). Sign out and delete call `Analytics.reset()`.

## Native setup
- iOS: `NSCameraUsageDescription` in `Info.plist` (English) and localised in
  `ios/Runner/{en,ar}.lproj/InfoPlist.strings` (a variant group in the Runner
  target; `ar` added to `knownRegions`); `CFBundleLocalizations` was already
  `en`, `ar`. The same text as the board.
- Android: `CAMERA` and `<uses-feature android.hardware.camera required="false"/>`
  (typing the code works without one).
- `mobile_scanner` uses the **bundled** ML Kit model on Android (works offline,
  about +3–10 MB). The unbundled variant (`dev.steenbakker.mobile_scanner.useUnbundled=true`)
  is smaller but downloads the model through Google Play services on first use.

## Docs read (2026-11-02)
- `supabase_flutter` 2.18.3 (already a dependency; latest on pub.dev): the
  source in the pub cache — `FlutterAuthClientOptions.localStorage`, the
  `LocalStorage` interface, `signInAnonymously(captchaToken:)`,
  `FunctionsClient.invoke` (non-2xx → `FunctionsHttpException`, no connection →
  `FunctionsFetchException`, `status` 0). supabase.com was not reachable.
- `mobile_scanner` 7.5.0 (published 2026-11-01): README (iOS
  `NSCameraUsageDescription`, Android bundled vs unbundled ML Kit),
  `MobileScannerController`, `MobileScannerErrorCode.permissionDenied`.
- `flutter_secure_storage` 11.2.0 (2026-09-16): changelog (11.x: Android minSdk
  24, `compileSdk` 37 — see "Check on the first CI build"), `IOSOptions`.
- `app_settings` 9.0.1 (2026-10-15): "Open settings" on the denied screen.
- Flutter 3.47.8 (`.fvmrc`), Android minSdk 26, iOS 15.

## Check on the first CI build
Built and tested here with `flutter test` only (no Xcode, no Android SDK, no
device): `flutter_secure_storage` 11 asks for `compileSdk` 37 in its Gradle
file (the changelog also says it uses `flutter.compileSdkVersion`); if the
Android build complains, raise `compileSdk` in `android/app/build.gradle*`.
The iOS project edit (`InfoPlist.strings`) was made by hand: open the project
once and check Runner → Resources lists *InfoPlist.strings (2)*. The camera,
the Keychain and `app_settings` need a real phone.

## Tests
- Unit: entities and `InviteCode.fromScan` (40+ hostile QR contents), every use
  case, both Supabase repositories (mocked client: statuses → reasons, replaced
  stale session, never replaced permanent session, wrong 200 bodies, last
  owner), secure storage, install id, the local cache (corrupt and hostile
  data), `AppFailure.from`.
- Widget + `screensUiTests` (32 variants each, goldens): welcome, scanner
  (live, refused, denied, no camera, offline), the outcome sheets (7), joined (4),
  workspace sheet (4), profile (+ add email, sign-out dialog), delete account (6),
  join (+ invalid), settings and home with the new rows.
- Flows (`gym_flows_test.dart`): type a code → Welcome → Today, wrong code,
  every refusal, retry offline, double tap, scan (valid, hostile, repeated frames,
  offline, denied), first screen rules, switcher, sign out, session ended
  elsewhere, delete (+ last owner), settings.
- Security: `test/security/deep_link_test.dart` (every new route, flag off,
  signed out, hostile paths), `platform_config_test.dart` (camera permission,
  Info.plist strings, no other permission), `gym_account_app_test.dart`.
- Integration (`integration_test/app_test.dart`, runs on the iOS simulator in
  CI): "join a gym: scan the QR, Welcome, then today's workout" with a fake
  camera and a fake gym.

## Not done here (next steps)
- Automatic deletion of the local copy after a confirmed import (decision §10).
- An automatic resume at app start for an interrupted copy (today: *Retry* or
  the *My account* row).
- Captain tools: step 4 (plan sync, rights and the toast are done: `workout.md`).
- Signing back in with the email added in Profile (an email one-time-code
  screen); today the email makes the account permanent and recoverable on the
  server, but the app has no sign-in screen for it.
- A visible Turnstile fallback (the widget runs invisibly; see `docs/release.md`).
- Showing an ended gym's readable history; the captain's name.

## Demo & post
Hook: "Scan your gym's QR. You're in."
Scenario (integration test): first launch → *Join your gym* → the scanner reads
the captain's QR → "Welcome to Iron House" and what you may change → *Start
training* → today's workout.
Captions: EN "Scan the QR your captain gave you. That's it, you're in the gym."
· AR "امسح الـ QR اللي إدهولك الكابتن. وخلاص، بقيت جوه الجيم."
Hashtags: #Azm #GymApp #Flutter #BuildInPublic
