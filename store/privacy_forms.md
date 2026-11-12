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
| Camera image | scanning a QR code | **never leaves the phone** | — | — |
| Rest notification content | rest timer | **never leaves the phone** | — | — |

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
- "Device or other IDs" covers the PostHog anonymous id (analytics) and the
  install id (sign-in, security). Both are random ids made by the app, not
  hardware ids.
- Not declared, because the app doesn't collect them: location, contacts,
  photos/videos (the camera image never leaves the phone), audio, files,
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
| Identifiers → **Device ID** (PostHog anonymous id) | Analytics |
| Usage Data → **Product Interaction** | Analytics |
| Search History → **Search History** (picture search words) | App Functionality |
| Diagnostics → **Crash Data** | App Functionality |
| Diagnostics → **Performance Data** | App Functionality |
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
