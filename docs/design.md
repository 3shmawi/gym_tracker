# Design

The UI is designed first in Claude (Design System + Design artifacts), then
built to match. Code never invents its own look.

| Source | Link |
|---|---|
| Design System (tokens, components, guidelines) | https://claude.ai/artifact/WUzyEppnEkcQXvVYec4m9H (source: `docs/design/workout_logging.html`) |
| Screens: Today, active workout, rest timer, superset, finish, states | same artifact, section 3 |
| Plan editor: days, a day's exercises, targets, add/rename and delete sheets, reorder, empty/locked/error states, entry points (boards 5.0–5.9) | https://claude.ai/artifact/KSeCy8hrBAPfgERNc32Am1 (approved Nov 2026) |
| Gym accounts: onboarding, scanner and its errors, enter code, Joined, solo-data question, gym switcher, profile (sign out, delete account), plan editor with permissions off, "captain updated your plan" toast, web join page, captain mobile companion, **web dashboard** for owners/captains (boards 1–12; decision: `docs/decisions/gym_accounts.md`) | https://claude.ai/artifact/XjCnp9ZLUVZ57o7pJ7odBu (approved Nov 2026) |
| Exercise library (app: add-exercise sheet, picker, exercise screen, Arabic/no results) and plan sharing in the captain's web dashboard (copy, template, one change for one member) (approved Nov 2026) | https://claude.ai/artifact/26EDAr572B4Qr8eBLB4D75 |
| Exercise media: gym-chosen pictures carousel (auto-advance rules, fallbacks, offline), how-to video card states, full player sheet (16:9 and Shorts), floating mini player over the workout and the rest timer (snap corners, no-go zones), library thumbnails, small phone / tablet (boards 1.1–5.3). Decisions: video thumbnail and title load when the screen opens; thumbnails go in the same temporary image cache as the pictures; the player is full width and at least 200×200 (YouTube's minimum), with black bands when needed. (approved Nov 2026) | https://claude.ai/artifact/VDxBpGdwNidSZgrGjfARJo |
| Captain dashboard D2, exercise media: exercise list, one exercise (pictures, library search, video link), Arabic RTL dark with a refused link and the 6 limit, states (boards D2.1–D2.4) (approved Nov 2026) | https://claude.ai/artifact/1hRNf6WxKvsmZ1vpK5S1YK |
| Exercise pictures on the home screen and the workout screen, the "How to do it" button, the floating workout pill (start / resume / rest / go, edge tab, with the video mini player), the settings layout, the plan fix for days 4 and 5 (boards 1–7, approved by the owner Nov 2026; the pill also showed on the home screen; changed 2026-11-11 by the owner: no pill on home, whose button says "Continue workout" during a workout) | https://claude.ai/artifact/6x6HnGjjC3BomfkW6fC9KU |
| Gym brand colours (D6, approved Nov 2026): dashboard settings with the colour picker, readability check and live phone preview; the app in a light and a dark gym colour, light and dark mode. Spec: `docs/designs/gym_brand_colours.md` | https://claude.ai/artifact/JwA9PRhZnLeYfYkvDWsjh2 |
| App icon (logo directions, 1b chosen) | https://claude.ai/artifact/26UTiBL3xuXEB8pKjCjn3L |

## Tokens → code
| Design System token | Code |
|---|---|
| Colors (light + dark) | `app_colors.dart` (raw tokens) → `app_palette.dart` (`context.palette`: trends, fills, text levels) + `AppTheme` ColorScheme |
| Brand colour (the green) | Widgets never read it from `AppColors`: fills use `context.palette.brand` / `onBrand` / `brandTint` / `brandDeep`, coloured text and icons use `colorScheme.primary`, the background uses `palette.glowStart` / `glowEnd`. `BrandColors` (`brand_colors.dart`) feeds `AppTheme.of(brightness, gymColor:)`; `brand_color_rule.dart` is the rule for a gym's colour (spec: `docs/designs/gym_brand_colours.md`). `test/core/theme/brand_color_usage_test.dart` fails on a direct use outside `lib/core/theme/`. Themes are cached per brightness, colour and screen scale. |
| Type scale, font family | `lib/core/theme/app_text_styles.dart` |
| Spacing, radius, sizes | `lib/core/theme/app_dimens.dart` |
| Components | `lib/core/ui/app_controls.dart` (exported by `app_ui.dart`): `AppPrimaryButton`, `AppSecondaryButton`, `AppStepper`, `AppBadge` (`AppTone`), `AppSetChip` (`AppSetState`). Showcase + tests: `test/core/ui/app_controls_test.dart` |

More components (plan editor): `AppDangerButton`, `AppTextField` (label,
helper/error, "n/40" counter, fixed direction), `AppSwitchRow` (adaptive
switch, whole row toggles), `AppChoiceChip` (48×48, weight step choices),
and `EmptyView(detail:)` for a second line under an empty state's title.

Gym account screens add `lib/core/ui/app_gym_controls.dart` (exported by
`app_ui.dart`): `AppLogoTile`, `AppOrb`, `AppListRow`, `AppRadioMark`,
`AppBanner`, `AppSectionLabel`, `AppViewfinder`, `AppCameraBackdrop`,
`AppChoiceCard`; and `AppDangerButton(style: tinted | outlined | solid)`.
Their deviations from the board are listed in `features/gym_account_app.md`.

When the Design System changes, update these files first, then screens.

## UI style: glass
Screens use `lib/core/ui/app_ui.dart` (`AppScaffold`, `AppCard`,
`AppIconButton`). With **glass** (Liquid Glass, iOS 26/27 look via
`liquid_glass_widgets`):
- Glass needs content behind it: give image-rich screens a photo
  `background:`; others get the brand gradient (`AppBackground`).
- At most two glass layers on top of each other. Premium quality (the iOS
  default) is for bars and buttons only — it captures the screen behind
  each surface. `AppCard` always uses the lightweight `standard` shader
  (`AppUi.cardQuality`), and a card that can grow taller than the screen
  (a whole history list) is `AppCard(tall: true)`: a flat card, no glass.
  One tall premium glass card on the history page used so much memory
  that iOS killed the app while scrolling (Sentry GYM_TRACKER-12).
  **Every glass card has no blur** (`AppUi.cardSettings`; the shader's
  tint, rim and highlight stay); bars, buttons and sheets keep theirs. The
  blur is a `BackdropFilter`: it re-blurred the screen behind each card's
  whole visible area on every scroll frame, which made scrolling heavy,
  worst under whole lists (`docs/performance.md`). Behind cards is only
  the brand gradient, which the blur barely changed: light looks the same;
  in dark cards are a little greyer and more see-through (approved by the
  owner, Nov 2026). `test/core/ui/app_scaffold_test.dart` checks it on
  Android and iOS. Progress and history stay `tall: true` (flat).
- Text on glass must stay ≥ 4.5:1 — test on the busiest photo, in light and
  dark, and with iOS 27's transparency slider at "clear".
- Accessibility: Reduce Motion and Increase Contrast are respected
  automatically; tests run with solid surfaces (`AppUi.testWrap`).
- Lite mode (`AppUi.isLite`: Reduce Transparency / Increase Contrast,
  widget tests, or `--dart-define=GLASS_LITE=true` for GPU-less devices)
  draws plain surfaces: no shader, no blur, no blurred shadow, no screen
  capture. New glass widgets in `app_ui.dart` need the same lite branch.
- `AppScaffold` places the body **below** the glass bar
  (`GlassScaffold(extendBody: false)`), not behind it: screens don't add a
  spacer for the bar, and their top row was hidden and untappable under it.
- The bar: `leading` at the start edge (default: back when the page can
  pop; the workout screen passes close instead), the title after it, and
  `actions` at the end edge. Icon buttons are 48×48 (`.ib` in the design);
  `test/core/ui/app_scaffold_test.dart` checks the glass bar in English and
  Arabic for overlaps, because screen tests only draw the lite bar.
- A screen that ends in a dock passes `padBottom: false` and pads the dock
  itself (`SafeArea(top: false)`), so the dock reaches the bottom edge
  instead of stopping above a strip of background.
- iOS icons come from `CupertinoIcons` (`core/adaptive/`), whose font is
  the `cupertino_icons` package: without it every iOS icon was a "?" box.
- When Flutter ships official Cupertino Liquid Glass, swap the
  implementation inside `app_ui.dart` only.

## Fonts
`AppFonts.latin` + `AppFonts.arabic` (lib/core/theme/app_fonts.dart), bundled
from Google Fonts in `assets/fonts/` (static TTF per weight, licenses shown on
the app's licenses page). Arabic characters fall back to the Arabic font
automatically. To change fonts: run
`python3 <kit>/kit_tools/fetch_fonts.py assets/fonts "<Latin>" "<Arabic>"`,
update the `fonts:` section in pubspec.yaml and the two constants.

## App icon & splash
The icon is **1b · Lifter + sets** from the logo canvas
(https://claude.ai/artifact/26UTiBL3xuXEB8pKjCjn3L): a glass figure pressing a
green barbell, then two rising bars (the tallest green) on the dark brand
gradient. `assets/branding/` holds the exports (made from the same SVG):
`icon.png` (1024, no transparency), `icon_foreground.png` (1024, transparent,
mark inside the middle 66%), `icon_staging.png` / `icon_dev.png` (STG / DEV
band), `splash.png` (768, transparent). The splash background is `#07120C`.
Android 8+ prod uses an adaptive icon
(`android/app/src/prod/res/mipmap-anydpi-v26/ic_launcher.xml`: background
`#0B3B24`, foreground and themed-icon monochrome from `icon_foreground.png`
in `drawable-*dpi/`); staging keeps the square icon so its STG band shows.
After changing the exports:
```bash
dart run flutter_native_splash:create
dart run flutter_flavorizr -f -p android:icons,ios:icons
```
then resize `icon_foreground.png` into the prod `drawable-*dpi/ic_launcher_foreground.png`
(108/162/216/324/432 px). For the full iOS 26 Liquid Glass look, rebuild the
icon in Apple's Icon Composer from the same layers (background, figure, bars).

## Motion: splash and loading
The approved logo animation is in `docs/design/motion/` (source of truth:
`splash_animation.dc.html`, 2.6 s). The app draws it with
`AzmLogoAnimation` (`lib/core/ui/`, exported from `app_ui.dart`), a 1:1
port: same shapes in the 100-unit box, gradients, keyframes, easing and
transform origins. Figures only: **no wordmark** in the splash or loading.
Frames are checked against the .dc.html rendered in Chromium
(`test/core/ui/azm_logo_reference_test.dart`).
- **Splash:** the native splash (static mark on `#07120C`) hands off to
  `AnimatedSplash`, which plays the animation once at
  `AzmLogoAnimation.nativeSplashSize` (166) so the end frame sits exactly on
  the native mark. Full on the first launch of the day, static after that;
  never waits longer than start-up; 250 ms cross-fade into the app.
- **Loading:** `LoadingView` loops it (no spinner): `LoadingSize.inline`
  (48), `card` (96), `screen` (166, default). Transparent background; in the light theme the
  white lines (glass edges, arms, muscle details) are drawn dark (`#0C1610`) instead so the figures
  show (`AzmLogoAnimation(brightness:)`), everything else is unchanged.
- Reduce Motion: the static logo. Screen readers: one "Loading" /
  "جاري التحميل" label, the parts are excluded.
- Never mirrored in Arabic (it is the logo).

## Level figures
The beginner / intermediate / pro figures come from
`docs/design/motion/level_figures.dc.html` (symbols `lv1`, `lv2`, `lv3`,
60×70 box), ported 1:1 in `AzmLevelPainter` (`lib/core/ui/azm_level_painter.dart`,
a part of `azm_logo_painter.dart`: `lv2` and `lv3` are the logo's heavy-lift
and flex figures, painted from the same shapes). `AzmLevelFigure` (exported
from `app_ui.dart`) is static, transparent, never mirrored, one image to
screen readers with the design's description, and draws its white lines dark
on light backgrounds (`brightness:`). `test/core/ui/azm_level_reference_test.dart`
compares it with Chromium renders of the .dc.html (`scripts/level_reference.js`).
The home screen's `LevelCard` shows it at `AppDimens.levelFigure` (48).

## Screen checklist (each screen in the design → code)
- Matches the design at 375×812, and still works on a small phone (320 wide),
  a large phone and a tablet.
- Has all states: loading (`LoadingView`, the looping logo), empty, error with
  retry, success, offline.
- Arabic RTL and dark mode checked.
- Touch targets ≥ 48×48, text contrast ≥ 4.5:1, works with large text
  (system font scale 1.3+), every icon button has a semantics label/tooltip.
- Motion: short (150–300 ms), purposeful; respects "reduce motion".
- Platform-adaptive: iOS look on iOS (Cupertino), Material on Android.

## UI testing (every screen, before every commit)
Three layers, all automatic except the last look:

1. **`screensUiTests({'<name>': () => MyView(...), ...})`**, called once,
   last, in the screen's widget test with every screen/state of the file (`test/helpers/ui_check.dart`). It runs the screen
   on 4 devices (320×568, 375×812, 430×932, 820×1180) × English/Arabic ×
   light/dark × text size 1.0/1.3 (32 variants) and fails when:
   - a RenderFlex overflows or a box sticks out of the screen,
   - text is cut off / ellipsized,
   - text is smaller than 11 px, or bigger than 40 px (except tabular hero
     numbers like the rest timer, ≤ 76 px),
   - the screen scale leaves 0.9–1.15 (a tablet must not show a zoomed phone),
   - text isn't in Inter/Cairo (a style without the app font falls back to
     SF/Roboto and loses Cairo for Arabic),
   - tap targets < 48, unlabeled buttons, or text contrast < 4.5:1.
   `test/helpers/ui_check_test.dart` proves each check catches its bug.
2. **Golden screenshots** of 4 key variants per screen in
   `test/**/goldens/<name>/`, with the real fonts. CI compares them; a visual
   change fails the build and uploads before/after/diff images
   (`ui-screenshot-diffs` artifact). Goldens are made on Linux
   (`dart_test.yaml` tag `golden`); on macOS run `flutter test -x golden`.
3. **Look at it.** `./scripts/ui_review.sh` regenerates every screenshot and
   builds `build/ui_review/index.html`. Check that sizes match across
   screens, nothing is too big or too small, Arabic is mirrored and dark mode
   reads well. Commit the updated goldens with the code.

The iOS simulator run is the integration test in CI (`integration` job) and
the **Demo video** workflow, which records it with full Liquid Glass.

Light-theme trend colors were darkened from the first design draft
(up `#166534`, down `#92400E`): the draft values only reached 3.6:1 on
their badge tint. Small text (≤ 14) never shrinks below its design size.
Contrast is checked on the English variants; the test font has no Arabic
glyphs, and Arabic uses the same colors.

Sizes: everything goes through `AppDimens.scaled()` / `AppTextStyles`. The
scale follows the screen width but is clamped to 0.9–1.15, touch targets
never drop below 48, and `AppScaffold` content is at most 600 wide on
tablets. Tests and the app share `AppScreenScale`, so tests measure what
devices show.
