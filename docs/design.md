# Design

The UI is designed first in Claude (Design System + Design artifacts), then
built to match. Code never invents its own look.

| Source | Link |
|---|---|
| Design System (tokens, components, guidelines) | https://claude.ai/artifact/WUzyEppnEkcQXvVYec4m9H (source: `docs/design/workout_logging.html`) |
| Screens: Today, active workout, rest timer, superset, finish, states | same artifact, section 3 |
| App icon (logo directions, 1b chosen) | https://claude.ai/artifact/26UTiBL3xuXEB8pKjCjn3L |

## Tokens → code
| Design System token | Code |
|---|---|
| Colors (light + dark) | `app_colors.dart` (raw tokens) → `app_palette.dart` (`context.palette`: trends, fills, text levels) + `AppTheme` ColorScheme |
| Type scale, font family | `lib/core/theme/app_text_styles.dart` |
| Spacing, radius, sizes | `lib/core/theme/app_dimens.dart` |
| Components | `lib/core/ui/app_controls.dart` (exported by `app_ui.dart`): `AppPrimaryButton`, `AppSecondaryButton`, `AppStepper`, `AppBadge` (`AppTone`), `AppSetChip` (`AppSetState`). Showcase + tests: `test/core/ui/app_controls_test.dart` |

When the Design System changes, update these files first, then screens.

## UI style: glass
Screens use `lib/core/ui/app_ui.dart` (`AppScaffold`, `AppCard`,
`AppIconButton`). With **glass** (Liquid Glass, iOS 26/27 look via
`liquid_glass_widgets`):
- Glass needs content behind it: give image-rich screens a photo
  `background:`; others get the brand gradient (`AppBackground`).
- At most two glass layers on top of each other; lists of many cards use
  `GlassQuality.minimal` to keep scrolling smooth on mid-range Android.
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

## Screen checklist (each screen in the design → code)
- Matches the design at 375×812, and still works on a small phone (320 wide),
  a large phone and a tablet.
- Has all states: loading (skeleton/adaptive spinner), empty, error with
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
