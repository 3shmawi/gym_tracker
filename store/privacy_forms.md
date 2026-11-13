# Store privacy forms: Google Play Data safety and Apple App Privacy

The answers to type into Play Console (**App content → Data safety**) and App
Store Connect (**App Privacy**), worked out from the code on 2026-11-04.
Update this file, `website/privacy.html` and the forms together whenever the
app starts sending something new.

Definitions used (read 2026-11-04):
- Google Play, "Provide information for Google Play's Data safety section"
  (support.google.com/googleplay/android-developer/answer/10787469): data
  processed **ephemerally** (in memory, only to serve the request in real
  time) is declared in the form but not shown on the listing; sending data
  to a **service provider** that processes it on our behalf is not
  "sharing".
- Apple, "App privacy details on the App Store"
  (developer.apple.com/app-store/app-privacy-details/): "collect" means sent
  off the device and kept for longer than needed to serve the request in
  real time; data used for tracking must say so (we track nothing).

## What leaves the phone (the inventory)

| What | When | Where it goes | Kept | Linked to the person |
|---|---|---|---|---|
| Display name (given by the gym), role | joined a gym | Supabase | while the account exists | yes |
| Account id (random) | joined a gym | Supabase | while the account exists | yes |
| Install id (random, made by the app, not a device id) | joined a gym | Supabase (sign-in) | while the account exists | yes |
| Email | only if the member adds one | Supabase Auth | while the account exists | yes |
| Manager email (captain dashboard, web) | an owner or captain signs in at `azmm-dash.pages.dev` | Supabase Auth (sign-in code email), Cloudflare (hosting) | while the account exists | yes |
| Workouts, plan, best level, chosen day | logged **in a gym**, or the member **turns on backup** (otherwise they stay on the phone) | Supabase | while the account exists | yes |
| Failed join attempts with a **hashed** network address | a wrong code | Supabase | 30 days | no |
| Bot check signals (Turnstile) | joining a gym | Cloudflare | Cloudflare's addendum | no |
| Usage events + random analytics id (PostHog anonymous id; `identify` is never called) | always | PostHog | PostHog retention | no |
| Crash reports + performance traces (device model, OS, app version; `sendDefaultPii = false`, no user set) | errors | Sentry | Sentry retention | no |
| Picture search words (exercise/muscle names) | solo member searches pictures | Supabase | not stored by us (request logs only) | no |
| IP address (download) | pictures (Cloudinary), video title/thumbnail and player (YouTube) | Cloudinary, Google | not kept by us | no |
| ML Kit usage metrics: device model and OS, ML accelerators, app package and version, a **per-installation id** (not a device id), latency, API configuration (image format and size), input/output size, event types, error codes | a Move game's camera round (pose detection); the QR scanner on Android (barcode scanning) | Google (ML Kit), as the app's SDK; not shared with third parties | Google's retention | no (no account or person id goes with it) |
| Camera image | scanning a QR code, a Move game's camera round | **never leaves the phone** (analysed frame by frame in memory, then dropped) | — | — |
| Body positions (landmarks) worked out from the camera | a Move game's camera round | **never leave the phone** (not stored, not in analytics, logs or crash reports) | — | — |
| Reps of a Move round | the member taps *Save to my training* | the phone; then like any workout (a gym's upload, backup if on) | like any workout | like any workout |
| Rest notification content | rest timer | **never leaves the phone** | — | — |

## Move games and Google ML Kit (added 2026-11-13)
Move games count reps with the front camera and Google ML Kit pose detection
(`google_mlkit_pose_detection`, bundled model). The QR scanner already used
ML Kit barcode scanning on Android (`mobile_scanner`; Apple's Vision on iOS),
so ML Kit's metrics were already sent before Move games; this update
declares them for both.

Sources read 2026-11-13:
- ML Kit "Prepare for Google Play's data disclosure requirements"
  (developers.google.com/ml-kit/android-data-disclosure, last modified
  2025-05-14): for **bundled** features ML Kit collects device information,
  application information, **per-installation identifiers that are not
  intended to uniquely identify a user or physical device**, performance
  metrics, API configuration, feature input/output size, feature version,
  event type and error codes, "used for diagnostics and usage analytics",
  encrypted in transit, **not transferred to third parties**. (Only *thin*
  features send a device identifier; pose detection and the scanner's
  model are bundled.)
- ML Kit "Prepare for Apple's App Store data disclosure requirements"
  (developers.google.com/ml-kit/ios-data-disclosure): the same list for all
  iOS features, with per-installation identifiers.
- Apple "App privacy details" (developer.apple.com/app-store/app-privacy-details/):
  *Device ID* is "the device's advertising identifier, or other
  device-level ID"; *Performance Data* is "launch time, hang rate, or energy
  use"; *Other Diagnostic Data* is "any other data collected for the purposes
  of measuring technical diagnostics related to the app".

What changes in the forms:
- **Google Play:** no new data type. *App info and performance →
  Diagnostics* and *Device or other IDs* are already declared (collected,
  not shared, purpose Analytics); ML Kit is one more source. *Photos and
  videos* stay **not collected**: the camera image is processed only on the
  device, which Google's form doesn't count as collection.
- **Apple:** add **Diagnostics → Other Diagnostic Data** (not linked,
  Analytics) for ML Kit's event types, API configuration and error codes;
  add **Analytics** as a purpose of **Performance Data** (ML Kit's latency).
  ML Kit's per-installation id is not a device-level id by Apple's
  definition; it is still listed under the **Device ID** row we already
  declare (not linked, Analytics), which is the safer reading. Camera and
  body data: nothing to declare (not collected).
- **iOS:** since 2026-11-13 the iOS app has the model and calls ML Kit in
  Move games on a real iPhone (never on the simulator); the answers above
  cover it. The iOS QR scanner still uses Apple's Vision, not ML Kit.

## Captain dashboard (web, managers only)
The captain dashboard (`dashboard/`, https://azmm-dash.pages.dev) is a website
for gym owners and captains, not part of the mobile app. A manager gives an
**email address** to get a one-time sign-in code (Supabase Auth); the session
is kept in their browser. It has no analytics, no tracking and no ads. It is
**not** part of the app's App Privacy / Data safety answers: the app never
asks a trainee for an email (only if they add one in Profile, already listed
above), and the dashboard is a separate web service. It is listed here and in
`website/privacy.html` ("Captain dashboard") so the forms stay accurate: if
the dashboard ever shows up inside the app, or adds analytics, update both
forms. Checked 2026-11-04.

## Google Play: Data safety

**Data collection and security**
- Does your app collect or share any of the required user data types? **Yes**
- Is all of the user data collected by your app encrypted in transit? **Yes**
- Do you provide a way for users to request that their data is deleted?
  **Yes**. In the app (Profile → Delete account), and the URL:
  `https://azmm.pages.dev/delete-account.html`

**Data types**: collected (not shared: every recipient is a service provider
processing on our behalf).

| Category → type | Collected | Shared | Ephemeral | Required / optional | Purposes |
|---|---|---|---|---|---|
| Personal info → **Name** | yes | no | no | optional (only for gym members) | App functionality, Account management |
| Personal info → **Email address** | yes | no | no | optional | Account management |
| Personal info → **User IDs** | yes | no | no | optional (gym members) | App functionality, Account management |
| Health and fitness → **Fitness info** | yes | no | no | optional (gym members) | App functionality |
| App activity → **App interactions** | yes | no | no | required | Analytics |
| App activity → **In-app search history** | yes | no | yes | optional | App functionality |
| App info and performance → **Crash logs** | yes | no | no | required | Analytics |
| App info and performance → **Diagnostics** | yes | no | no | required | Analytics |
| Device or other IDs → **Device or other IDs** | yes | no | no | required | Analytics, Fraud prevention, security, and compliance |

Notes for the form:
- "Device or other IDs" covers the PostHog anonymous id (analytics), the
  install id (sign-in, security) and ML Kit's per-installation id
  (diagnostics). All are random ids, not hardware ids.
- "Diagnostics" covers Sentry's performance traces and ML Kit's usage
  metrics (Move games, the QR scanner on Android).
- Not declared, because the app doesn't collect them: location, contacts,
  photos/videos (the camera image never leaves the phone: QR scanner and
  Move games), audio (the microphone is never used), files,
  messages, financial info, web history, installed apps.
- **Owner's decision (recorded 2026-11-03, unchanged):** IP addresses seen by
  Cloudinary and YouTube while serving a download are not declared. We don't
  receive or keep them, and Google Play has no "IP address" data type.

### Check before submitting (dashboard settings this repo can't see)
- **PostHog:** by default, PostHog's servers can add a GeoIP (city/country)
  to each event from the phone's IP address. Either turn on **Project
  settings → "Discard client IP data"** (then nothing changes here), or also
  declare **Location → Approximate location** (Analytics) for Google and
  **Location → Coarse Location** (not linked, Analytics) for Apple.
- **Sentry:** `sendDefaultPii` is off in the app. Also turn on **Project
  settings → Security & Privacy → "Prevent storing of IP addresses"**, so
  the answers above stay true.

## Apple: App Privacy

- **Do you or your third-party partners collect data from this app?** Yes
- **Tracking:** **No**. Nothing is linked with third-party data for
  advertising, and nothing goes to data brokers. No ATT prompt is needed.

**Data linked to the user** (gym accounts):

| Type | Purposes |
|---|---|
| Contact Info → **Name** | App Functionality |
| Contact Info → **Email Address** | App Functionality |
| Identifiers → **User ID** (account id, install id) | App Functionality |
| Health & Fitness → **Fitness** (logged workouts) | App Functionality |

**Data not linked to the user:**

| Type | Purposes |
|---|---|
| Identifiers → **Device ID** (PostHog anonymous id; ML Kit's per-installation id) | Analytics |
| Usage Data → **Product Interaction** | Analytics |
| Search History → **Search History** (picture search words) | App Functionality |
| Diagnostics → **Crash Data** | App Functionality |
| Diagnostics → **Performance Data** (Sentry; ML Kit latency) | App Functionality, Analytics |
| Diagnostics → **Other Diagnostic Data** (ML Kit event types, API configuration, error codes) | Analytics |
| Other Data → **Other Data Types** (hashed network address of failed join attempts; Turnstile bot check) | App Functionality (fraud and abuse prevention) |

- **Privacy Policy URL:** `https://azmm.pages.dev/privacy.html`
- Pictures (Cloudinary) and how-to videos (YouTube) are served in real time
  and not kept by us, so they're not "collected" by Apple's definition. Both
  are named in the privacy policy.

## In the app (YouTube API Services Developer Policies III.A, checked 2026-11-04)
- The member must agree to the privacy policy **before** using the app
  (`lib/core/legal/`):
  - **New members** see the welcome screen. Under the choices: "By continuing,
    you agree to the Terms of Use, the Privacy Policy and YouTube's Terms of
    Service", with the three links. Choosing join, code or solo records the
    agreement (`acceptTerms(via: welcome)`), with no extra screen.
  - **Everyone else** (members from before, or the welcome screen not
    shown): `ConsentGate` opens a one-time sheet "Before you start" over the
    screen, with the four links (Privacy Policy, Terms of Use, YouTube Terms
    of Service, Google Privacy Policy) and **Agree and continue**. It can't be
    swiped, tapped or backed away. On the welcome screen it waits.
  - Never behind a feature flag or shown only during store review: that would
    be misleading the reviewers (App Store Review Guideline 2.3.1, Google
    Play's Deceptive Behavior policy), and YouTube's rule is for every user.
- The member must agree again when the policy changes:
  `ConsentStore.current` equals the policy's "Last updated" date, and
  `test/security/store_pages_test.dart` fails if they drift apart.
- The policies are always reachable: Settings → About → Privacy Policy /
  Terms of Use.
- The privacy policy names YouTube API Services and links the Google Privacy
  Policy (since 2026-11-03).
