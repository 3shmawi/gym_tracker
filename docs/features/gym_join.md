# Feature: join a gym by link or code

> Step 1/3 of the delivery plan in [`../decisions/gym_accounts.md`](../decisions/gym_accounts.md) §13
> (website + the app's `/join` route). Redeeming a code (sign-in, Supabase) is
> step 3/4 and not here.

## What it does
- **Web page** `https://azmm.pages.dev/join/<code>` (`website/join.html`): what a
  phone shows after scanning the QR when the app is not installed, or when
  the link opens in an in-app browser. It shows the code in big text ("type this
  after installing"), **Open in Azm** (`azm://join/<code>`), the store button
  for the phone (App Store on iPhone, Google Play on Android, both elsewhere),
  and a copy button. A computer gets two columns and both stores. English and
  Arabic (browser language, switch on desktop).
- **App route** `/join/<code>` and `/join` (same for `azm://join/<code>`): the
  "Enter your gym code" screen with six boxes. A link only **pre-fills** the
  code (with the banner "We opened the link and typed the code for you"); the
  member taps **Join** to confirm. A link with no valid code shows an empty
  field and "This link has no valid code".
- Behind the **`gym_join`** feature flag (PostHog), off by default: off, the
  links open the home screen like before. While joining is not built the Join
  button stays off and a line says "Joining a gym arrives in the next update".

## Design
Copied from the approved gym accounts design (boards 3, 8a, 8b, `extra.css`):
same sizes, radii, colors and spacing. Web: Inter and Cairo served from the same
site (`website/assets/fonts`, `@fontsource` 5.3.0, OFL, checked 2026-11-02), no
Google Fonts, so the page makes no third-party request. App: `AppCodeField`
(six boxes, 62 high, 16 radius, 28 px / 800, always left-to-right) in
`lib/core/ui/app_controls.dart`; a disabled primary button is now the design's
quiet chip (`.cta.off`) everywhere.

## Files
| What | Where |
|---|---|
| Web page, styles, logic, rewrite, headers | `website/join.html`, `assets/join.css`, `join-nojs.css`, `join-code.js` (pure logic), `join.js` (DOM), `assets/fonts/`, `_redirects`, `_headers` |
| Code value type (parse, clean) | `lib/features/gym/domain/entities/invite_code.dart` |
| Screen | `lib/features/gym/presentation/join_view.dart` (pure UI), `join_page.dart` (wires the link), `join_submit.dart` (what Join does, null until joining exists) |
| Route, flag | `lib/core/router/app_router.dart` (`join`, `join_code`), `AppRoutes.join`, `Flags.gymJoin` |
| Strings | `lib/l10n/app_en.arb`, `app_ar.arb` (`join*`) |

## Rules this keeps (docs/security.md → "Join page")
- The code from an address is untrusted. Web: only the **path** is read, checked
  with `^[A-HJKMNP-Z2-9]{6}$` after an ASCII-only check, and written with
  `textContent`; no `innerHTML`, `document.write`, `eval`, query or hash.
  App: `InviteCode.tryParse` is the only way a code reaches the screen.
- A link **cannot sign in by itself**: `joinSubmitProvider` runs only after the
  member's tap (tested with a counter, also after time passes and the app is
  backgrounded).
- No trackers, no backend calls, no logging of the code; `InviteCode.toString`
  never prints it. The page is `no-store`, `noindex`, `no-referrer`.

## Tests
- `test/features/gym/domain/invite_code_test.dart` — valid, case, spaces,
  hostile text, look-alikes (`ß ſ Ａ`), `clean()`.
- `test/features/gym/presentation/join_view_test.dart` — typing, paste, hostile
  input, link banner, incomplete link, not-ready state, accessibility, and
  `screensUiTests` (4 states × 32 variants, goldens reviewed).
- `test/security/deep_link_test.dart` — flag off (home), flag on: valid code
  fills the field and submits nothing, hostile codes, extra paths, `?c=` ignored,
  never joins without a tap.
- `test/security/join_page_test.dart` — the page never uses `innerHTML` or
  `document.write`, no inline script/style, no third parties or trackers, store
  links equal the home page's, `/join/*` rewrite and `no-store` headers, no `?c=`.
- `test/website/join_code.test.js` (`node --test`, CI) — address parsing,
  platform detection, and `join.js` against a fake DOM.
- `integration_test/app_test.dart` — "an invite link fills in the code and
  waits for the tap" (runs on the iOS simulator in CI).

## Edge cases
- Code in lower case or with `%`-encoded characters: accepted after decoding.
- `0 O 1 I L`, 5 or 7 characters, non-ASCII look-alikes, `<script>`, SQL-like
  text, 5,000 characters, `javascript:`, a URL as the code: "no valid code".
- `/join` with no code: page says "link incomplete" (web) / empty screen (app).
- No JavaScript: the buttons and both languages work; the code is not shown (it
  lives in the address; the page says so).
- Opening a second link while the screen is open starts it over (the old code
  is not kept).
- Universal/App Links are unchanged (`/join/*` only, no query), so a link
  `?c=` is never claimed.

## Not done here
- The store button for iOS still points to the placeholder app id
  (`idYOUR_APP_ID`, same as the home page; both must change together, a test
  keeps them equal).
- The scanner screen, Joined/solo-data screens and the redeem call (delivery
  steps 3/4).
- Analytics for the screen: the screen name comes from the route names
  (`join`, `join_code`); `gym_join_started` etc. arrive with the redeem step.

## Demo & post
Hook: "Scan the QR your captain gave you and your gym is already typed in."
Scenario (integration test): open an invite link, see the six boxes filled and
the banner, open a broken link and see the message, type a code by hand.
Captions: EN "Scan. It's typed for you. You tap Join." · AR "امسح الكود، هيتكتب
لوحده، وإنت تدوس انضم." Hashtags: #Azm #GymApp #Flutter #BuildInPublic
