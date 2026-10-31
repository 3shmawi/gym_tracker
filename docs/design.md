# Design

The UI is designed first in Claude (Design System + Design artifacts), then
built to match. Code never invents its own look.

| Source | Link |
|---|---|
| Design System (tokens, components, guidelines) | https://claude.ai/artifact/WUzyEppnEkcQXvVYec4m9H (source: `docs/design/workout_logging.html`) |
| Screens: Today, active workout, rest timer, superset, finish, states | same artifact, section 3 |
| App icon / store screenshots | <!-- claude.ai/artifact/… --> |

## Tokens → code
| Design System token | Code |
|---|---|
| Colors (light + dark) | `lib/core/theme/app_colors.dart` → `AppTheme` |
| Type scale, font family | `lib/core/theme/app_text_styles.dart` |
| Spacing, radius, sizes | `lib/core/theme/app_dimens.dart` |
| Components (buttons, cards, inputs…) | `lib/core/widgets/` (create as needed) |

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
`assets/branding/` holds a placeholder generated in the primary color.
Export the real icon from Claude Design and overwrite (same names/sizes):
`icon.png` (1024, no transparency), `icon_foreground.png` (1024, transparent,
mark inside the middle 66%), `icon_dev.png` / `icon_staging.png` (flavors),
`splash.png` (768, transparent). Then:
```bash
dart run flutter_native_splash:create
dart run flutter_launcher_icons            # single-flavor projects
dart run flutter_flavorizr -p android:icons,ios:icons   # projects with flavors
```

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

1. **`screenUiTests('<name>', () => MyView(...))`**, the last call in the
   screen's widget test (`test/helpers/ui_check.dart`). It runs the screen
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

Sizes: everything goes through `AppDimens.scaled()` / `AppTextStyles`. The
scale follows the screen width but is clamped to 0.9–1.15, touch targets
never drop below 48, and `AppScaffold` content is at most 600 wide on
tablets. Tests and the app share `AppScreenScale`, so tests measure what
devices show.
