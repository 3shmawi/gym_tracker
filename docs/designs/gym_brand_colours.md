# Design: gym brand colours (dashboard D6)

> **Status: approved by the owner on 2026-11-11, with every recommendation
> under "Decisions" below.** Written by hand with EGM's sections: the plugin's
> `/egm:` commands can only be started by a person, and no EGM review was
> run before the approval.
>
> Builds on D5 (#75) and on gym settings being owner-only (migration 0020,
> [#76](https://github.com/3shmawi/gym_tracker/pull/76)); both are on `main`.

Mockup (dashboard settings with a working picker, and the app in two gym
colours, light and dark): https://claude.ai/artifact/JwA9PRhZnLeYfYkvDWsjh2
The mockup runs the exact colour rule of this spec. 

## Goal
The gym owner picks the gym's colour in the dashboard and sees a live phone
preview. The gym's members get that colour in the app while that gym is their
active workspace. Solo training keeps Azm's colours. A saved colour can never
make the app hard to read.

## What exists today (checked 2026-11-11)
- **Theme:** `AppTheme._build` seeds `ColorScheme.fromSeed(AppColors.primary)`
  and pins `primary`, `onPrimary`, `surface`, `onSurface`, `onSurfaceVariant`,
  `error`. `AppPalette` (a `ThemeExtension`) holds surfaces, text greys and
  trend colours. `MaterialApp.router` gets `AppTheme.light` / `.dark`.
- **The green is used in three roles:**
  1. *fill*: `AppColors.primary` + `AppColors.onPrimary` (buttons, progress,
     the workout pill, selected marks), the same value in light and dark;
  2. *accent*: `colorScheme.primary` for coloured text, icons and borders
     (`#22C55E` in dark, `#15803D` in light), about 45 uses in 25 files,
     already theme-driven;
  3. *glow*: `AppBackground` mixes `AppColors.primary` into the background.
- **Direct uses to remove:** 23 in 7 files (list under "App refactor").
- **A second colour:** the app has none. `colorScheme.tertiary` is read once
  (the far corner of the background glow); `secondary` is never read.
- **Gym data:** `SupabaseGymRepository._fetchRows` selects
  `memberships` with `gyms(id, name, history_after_end)`. The result is cached
  in `SharedPreferences` (`gym.memberships`) and refreshed at start, on resume
  and when the network returns (`GymController.refresh`).
- **Who writes `gyms`:** after #76 only the owner (`private.i_own`), on the
  columns `name`, `logo_path`, `history_after_end`. Members (also ended ones)
  can select their gym's row. `anon` has nothing.
- **Dashboard:** `SettingsPage.tsx` + `gyms/settings.ts`; owner edits,
  captain sees read-only. CSP is `style-src 'self'`. No analytics, no flags.
- **Contrast today:** the fill `#22C55E` is 7.5:1 on the dark card but only
  2.0:1 on the light background; accent `#15803D` is 4.50:1 on it.

## Decisions

### 1. The owner picks one colour
One `#rrggbb` value. No accent colour: the app does not use a second colour
today, so there is nothing for it to change. It can be added later as a
second column without touching this one.

### 2. The colour rule (the same in the app and the dashboard)
From the picked colour `C` and the mode, the app makes four values. All
arithmetic is on integers, so Dart and TypeScript give the same bytes.

| Value | Used for | Rule | Guarantee |
|---|---|---|---|
| `brand` | fills: buttons, progress, pill, selected marks | `C` mixed toward black (light mode) or white (dark mode) in 1% steps, the first step with contrast ≥ 3:1 against the mode's reference surface | ≥ 3.0:1 (WCAG 1.4.11) |
| `onBrand` | text and icons on `brand` | white if white on `brand` is ≥ 4.5:1, else black | ≥ 4.5:1 (WCAG 1.4.3) |
| `primary` (accent) | coloured text, icons, borders on surfaces | same mixing, first step ≥ 4.5:1 | ≥ 4.5:1 |
| `onPrimary` | text on the accent used as a fill | same as `onBrand`, for `primary` | ≥ 5.0:1 |
| glow | the two tinted corners of `AppBackground` | `brand` mixed into the background (55% and 70% background), then more background until it is not stronger than Azm's own glow | text on the glow is never less readable than today |

- Reference surface: light `#EEF4F0` (the darker of the two light surfaces),
  dark `#141E19` (the lighter of the two dark ones). Passing on these passes
  on the other surface too.
- Mixing: `channel = (c × (100 − k) + target × k + 50) div 100`.
- Contrast: WCAG 2.2 relative luminance from a 256-entry table rounded to
  1e-6, compared as integers (`den × (hi + 0.05) ≥ num × (lo + 0.05)`), so a
  rounding difference between platforms can't flip a result.
- **Checked on all 16,777,216 colours in both modes** with the reference
  script: lowest `brand` 3.0000, `onBrand` 4.5000, `primary` 4.5000,
  `onPrimary` 5.02, main text on a 20% `brand` tint 8.29.
- Because the app makes the values itself, **any valid colour is safe**. The
  server does not need to re-check contrast, and the phone does not trust the
  server to have done so.

Examples (reference script, 2026-11-11):

| Picked | Light `brand` / accent | Dark `brand` / accent |
|---|---|---|
| yellow `#FACC15` | `#A8890E` (33% darker) / `#856C0B` | `#FACC15` (as picked) / `#FACC15` |
| red `#DC2626` | as picked / `#D52525` | as picked / `#E35151` |
| navy `#1E3A8A` | as picked / as picked | `#5065A4` (22% lighter) / `#7183B5` |
| purple `#6D28D9` | as picked / as picked | `#7F42DE` (12% lighter) / `#9A6BE5` |

The cost of the guarantee: a light colour is shown darker in light mode
(yellow becomes dark gold) and a dark colour lighter in dark mode. The
preview shows this before saving. See "Decisions needed" 2.

**Not a brand colour:** a value whose largest and smallest channel differ by
less than 40 (black, white, greys). The dashboard refuses it, the database
refuses it, and the phone treats it as "no colour".

**Azm's own colours are not generated.** They stay the hand-tuned constants
of the approved design, so the theme refactor changes no pixel. A gym that
picks exactly `#22C55E` gets the generated values (a slightly darker fill in
light mode).

Rejected: Material's `ColorScheme.fromSeed` roles for `brand`. Flutter's
docs say the seed "may not wind up as one of the ColorScheme colors"; an
owner would not see their own red. It would also need a second
implementation (an npm package) whose version can drift from Flutter's. The
unpinned Material roles (ripples, text selection) still come from
`fromSeed(seedColor: C)`.

### 3. What never changes per gym
Trend colours (up, keep, down, new), error red and danger buttons, the Azm
logo, splash, loading animation and level figures, the notification small
icon and its accent colour, the app icon, store listing, backgrounds,
surfaces and text greys (only the glow follows the gym), the scanner's
camera backdrop, the dashboard's own colours.

Also always Azm: everything shown without an active gym (welcome, join,
scanner, solo), the consent screen and the update gate.

### 4. Storage and access
Migration `0021_gym_brand_color.sql` (after 0020):

- `gyms.brand_color text` (null = Azm colours), with
  `check (brand_color is null or private.brand_color_ok(brand_color))`.
- `private.brand_color_ok(text)`: immutable, `search_path = ''`; true for
  `^#[0-9a-f]{6}$` (lower case, exactly 7 characters) whose channel spread is
  ≥ 40.
- `grant update (brand_color) on public.gyms to authenticated`. The existing
  policy "owners update their gym" (`private.i_own`) decides who.
- Reading: the existing table `select` grant and "members read their gyms".
  A colour is not personal data; an ended member can still read it and the
  app ignores it for them.
- `private.redeem_payload` also returns `brand_color`, so the "Joined"
  screen is already in the gym's colour.

Why one column and not a `theme` jsonb: nothing to validate key by key, the
column grant is exact, a `check` is enough, and the generated values are not
stored, so the rule can improve in an app release without a migration. An
accent later is one more column.

| | anon | member (active or ended) | captain | owner of another gym | owner on an anonymous session | owner |
|---|---|---|---|---|---|---|
| read `brand_color` | no | yes | yes | not this gym | yes | yes |
| write it | no | no (0 rows) | no (0 rows) | no (0 rows) | no (0 rows) | yes |

Supabase's docs (column-level security, read 2026-11-11) do not recommend
column privileges for most projects and note that restricted roles must
list columns. This table already uses them, both clients list columns, and
select stays table-wide, so the pattern is kept.

### 5. How the app gets it
- `brand_color` is added to the `gyms(...)` list of the membership query the
  app already makes, and to the cached JSON. **No new request, no new
  storage key.** It works offline from the cache.
- `BrandColor.tryParse` returns null for anything that is not a string of
  the exact format with enough colour; null means Azm. It never throws and
  never fails the membership.
- `Gym.brandColor` (nullable). `activeBrandColorProvider` reads it for the
  active, non-ended membership when the flag is on; otherwise null.
- **Theme seam:** `AppTheme.build(brightness, {BrandColors? brand})`.
  `BrandColors.azm` are the constants; `BrandColors.fromSeed(color,
  brightness)` is the rule above. `AppPalette` gains `brand`, `onBrand`,
  `brandTint`, `glowStart`, `glowEnd` (and a complete `copyWith`).
- **Where it is applied:** `MaterialApp` keeps Azm's themes. A
  `BrandThemeHost` inside `ConsentGate` (in `AppShell.builder`) wraps the
  navigator in `AnimatedTheme` (200 ms, none with Reduce Motion) with the
  gym's theme for the current brightness. So the consent screen stays Azm by
  construction; the update dialog and force-update screen wrap themselves in
  the Azm theme. Built themes are cached per (colour, brightness).
- The member's own light / dark / system setting picks the brightness as
  today; the gym only changes the colour inside it.
- **Must not happen:** a colour change must not rebuild
  `workoutRepositoryProvider` (it watches `activeMembershipProvider`, and
  `Gym ==` would now change). The scoped repository will depend on the
  membership id and permissions only; a test changes the colour during an
  active workout and checks the workout state survives.

### 6. App refactor (PR 1, no visible change)
All 23 direct uses move to the theme:

| File | Uses | Becomes |
|---|---|---|
| `core/ui/app_controls.dart` | 6 | `palette.brand`, `onBrand`, `brandTint` |
| `core/ui/app_gym_controls.dart` | 2 | `palette.brand`, `onBrand` |
| `core/ui/app_ui.dart` | 1 (glow) | `palette.glowStart`, `glowEnd` (Azm: today's exact computed values; `colorScheme.tertiary` is no longer read) |
| `workout/.../workout_pill_view.dart` | 8 | `palette.brand`, `onBrand` |
| `workout/.../rest_panel.dart` | 1 | `palette.brand` |
| `gym/presentation/profile_view.dart` | 3 | `palette.brand` (avatar gradient: `brand` to a darker mix), `onBrand` |
| `workout/data/services/notification_rest_alarm.dart` | 2 | `AppColors.notificationAccent` (fixed Azm, named so) |

`test/core/theme/brand_color_usage_test.dart` reads every file under `lib/`
outside `lib/core/theme/` and fails on `AppColors.primary`,
`AppColors.primaryText`, `AppColors.onPrimary` or the hex values
`22C55E` / `15803D`. Existing goldens must pass unchanged.

The seam is shared infrastructure; PR 1 will say whether it should also go
to flutter-project-kit (expected: yes, the seam and the usage test, not the
gym part).

### 7. Dashboard (owner only)
A "Brand colour" panel on the settings page, as in the mockup:
- the browser's colour input, a code field (`#RRGGBB`), seven starting
  colours;
- "What the app will use": light and dark samples with the generated values
  and a sentence when the colour was adjusted;
- "Readability check": the three ratios for light and dark;
- a refusal for an invalid code or a colour without enough colour (Save is
  off), and a note (not a refusal) when the colour is close to the error red;
- a live phone preview in light and dark: home with exercise pictures,
  active workout, the workout pill, a sheet;
- Save, and "Reset to Azm colours" (`brand_color = null`).

Captains see the saved colour and preview read-only, like the other
settings. Preview colours are set through the CSSOM (Preact `style`
objects), so the CSP is unchanged. The dashboard itself stays in Azm
colours. `GymSettingsRepository.setBrandColor` validates before any request
and treats 0 rows as `forbidden`, like `rename`.

### 8. Edge cases
| Case | Behaviour |
|---|---|
| Member's dark / light setting | Unchanged; the rule runs for that brightness. |
| Colour changes during a workout | Applied at the next refresh (start, resume, back online) with a short fade. Nothing but colour changes; no toast. |
| Several gyms | The active workspace decides; switching fades to the other gym's colour or to Azm for solo. |
| Ended member, missing membership | Solo, so Azm. |
| Demo gym | `brand_color` stays null: Azm. |
| Invalid, grey or unknown value from the server or the cache | Azm. |
| Flag off | Azm everywhere, even if a colour is saved. |
| Old app versions | They select named columns and never see the new one. |
| Update gate, consent | Always Azm. |
| Screenshots and goldens | Existing goldens unchanged; new goldens for two gym colours. Store screenshots stay Azm. |
| Offline at first start after joining | The colour came with the join answer; otherwise Azm until the first refresh. |

### 9. Rollout
- Flag `gym_brand_colours` (`Flags.gymBrandColours`, PostHog, off by
  default). The last known value is kept on the phone and used at start, so
  the app does not open green and then change.
- Order: PR 1 (any time) → PR 2 migration → PR 3 app → PR 4
  dashboard → turn the flag on. Each step is safe alone: an unused column, an
  app that reads null, a dashboard that writes a column old apps ignore.
- Events (app): `gym_theme_applied` `{mode: light|dark, adjusted: bool}` and
  `gym_theme_fallback` `{reason: invalid|flag_off}`. No colour value, no gym
  id. The dashboard has no analytics; that stays.
- Privacy policy: no change (a colour chosen by the gym, no personal data).

### 10. PR split
1. **App theme refactor**, no visible change: `BrandColors`, palette roles,
   the 23 uses, the usage test, the rule with unit tests and shared vectors.
2. **Backend:** migration 0021, `redeem_payload`, pgTAP.
3. **App reads the gym colour:** parsing, cache, provider, `BrandThemeHost`,
   flag, events, widget tests and goldens with gym colours, integration demo.
4. **Dashboard:** panel, preview, rule in TypeScript, vitest, Playwright,
   axe, security e2e.

### 11. Tests
- **Shared vectors** `docs/features/brand_colour_vectors.json` (picked colour
  → all generated values for both modes, valid / invalid codes). Read by the
  Dart tests, vitest, and pgTAP for the validity part.
- **Dart:** the rule over the vectors and a full sweep of the colour cube for
  the guarantees; `tryParse` with hostile input (wrong type, 3- and 8-digit
  codes, upper case, spaces, very long strings, injection-like text);
  provider (flag, ended, solo, switch); active workout survives a colour
  change; `screensUiTests` for home, workout, pill and a sheet in two gym
  colours; update gate and consent stay Azm.
- **pgTAP:** every cell of the access table; bad values refused (format,
  upper case, grey, long text, null allowed); no other column becomes
  writable; `redeem_payload` carries the colour.
- **Dashboard:** vitest for the rule and the repository; Playwright for
  pick, preview, save, reset, captain read-only; axe; security e2e with bad
  codes, a huge body, extra keys, injection-like strings and another gym's
  id.

### 12. Docs to update with the code
`docs/features/gym_brand_colours.md` (new), `dashboard.md` (D6),
`gym_accounts_backend.md`, `decisions/gym_accounts.md` §4, `design.md`
(tokens → code, the mockup), `security.md`, `docs/README.md`.

## Official docs checked (2026-11-11)
- Flutter 3.47.8 (`.fvmrc`): `ColorScheme.fromSeed` (`dynamicSchemeVariant`,
  `contrastLevel` −1 to 1, default 0; the seed may not appear in the
  scheme); `ThemeExtension` (`copyWith`, `lerp` for smooth theme changes).
- WCAG 2.2 (W3C Recommendation, 12 December 2024): 1.4.3 text 4.5:1, large
  text 3:1; 1.4.11 user interface components and graphics 3:1.
- Supabase: column-level security guide (above).

## Decisions (approved 2026-11-11: the recommended choice in each)
1. One colour only, no accent in this version. *Recommended: yes.*
2. Fills are adjusted to reach 3:1 (yellow becomes dark gold in light mode),
   or fills always use the exact colour as Azm's green does today (2.0:1 on
   light) and only text is adjusted. *Recommended: adjust.*
3. Black, white and grey are refused. *Recommended: yes.*
4. A colour close to the error red: a note only, or refused. *Recommended:
   a note.*
5. Backgrounds and text greys stay Azm's; only the glow follows the gym.
   *Recommended: yes.*
6. A colour change during a workout applies at once with a fade, or waits
   until the workout ends. *Recommended: at once.*
7. The demo gym keeps Azm colours. *Recommended: yes.*
8. Only the owner changes the colour; captains see it read-only (follows
   #76). *Recommended: yes.*
9. The "Joined" screen is already in the gym's colour (needs the
   `redeem_payload` change). *Recommended: yes.*
10. EGM review: approved without it.
