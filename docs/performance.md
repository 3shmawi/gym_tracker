# Performance

How to measure scrolling, what we measured, and what was changed.
Docs checked on 2026-11-03 for Flutter **3.47.8** (`.fvmrc`):
- "Flutter performance profiling" (docs.flutter.dev/perf/ui-performance,
  updated 2026-10-28): measure on a **real device in profile mode**;
  simulators and emulators don't show what users see; debug builds are JIT
  and misleading. Two threads matter: **UI** (build/layout, your Dart code)
  and **raster** (draws the layer tree on the GPU). Budget: 16 ms per
  frame at 60 Hz (8 ms at 120 Hz).
- "Impeller rendering engine" (docs.flutter.dev/perf/impeller, updated
  2026-08-21): Impeller is the default on Android API 29+ (Vulkan); older
  Android or devices without Vulkan fall back to the OpenGL renderer.
  `flutter run --no-enable-impeller` turns it off to compare. (`--trace-skia`
  only applies to the old Skia path.)
- "Measure performance with an integration test"
  (docs.flutter.dev/cookbook/testing/integration/profiling, updated
  2026-09-29): `flutter drive --driver=… --target=… --profile`, `--no-dds`
  on a phone. We use `IntegrationTestWidgetsFlutterBinding.watchPerformance`
  (engine `FrameTiming`s → `FrameTimingSummarizer`: average / 90th / 99th
  build and raster times, missed-budget frames).
- `liquid_glass_widgets` **1.16.1** (latest on pub.dev, published
  2026-10-30) README + source: `standard` quality draws one
  `BackdropFilter` (blur + saturation) **plus** a fragment shader per glass
  surface; on Impeller every `BackdropFilter` ends the render pass and
  copies the screen. `minimal` is blur only (still a `BackdropFilter`). The
  README: "Content areas (lists, cards, article tiles) stay opaque";
  "iOS renders inset-grouped list cards as flat, opaque surfaces" →
  `GlassSurfaceStyle.solid`.

## How to measure
The test: `integration_test/perf/scroll_perf.dart`. It seeds six weeks of
training on the 5-day plan, then flings each main list down and up three
times inside `watchPerformance`: home (next workout), plan day, exercise
library (`/library?day=…`), exercise screen (`/library/<id>`), progress,
exercise history, active workout. It is not a `_test.dart` file, so the
normal CI integration job (`flutter test integration_test`) doesn't run it.

**On your phone (the real numbers)**, profile mode, plugged in:
```bash
./scripts/perf.sh
```
```bash
./scripts/perf.sh --lite
```
Each prints a table and writes `build/perf/glass.{json,md}` and
`build/perf/lite.{json,md}`. Compare a fix with `--name before` on `main`
and `--name after` on the branch. Use the slowest phone you have; close
other apps; same battery/thermal state for both runs.

**By hand, to see where the time goes:**
```bash
flutter run --profile --flavor staging --dart-define-from-file=env/example.json
```
then press `P` for the performance overlay (top graph = raster, bottom =
UI; red bars are missed frames), or open DevTools → Performance and record
while scrolling. Raster red while UI is fine = the GPU work (glass, blur,
`saveLayer`); UI red = build/layout (rebuilds, big lists built eagerly).

**In CI, on demand:** add the **`perf`** label to a PR or run Actions →
**Performance**. It runs the test with glass, with `GLASS_LITE=true`, and
with glass on the base branch's `lib/` (same machine: before vs after), on
an iPhone simulator (debug: simulators can't run profile). Tables go to
the run summary, files to the `perf-ios` artifact (frame times only, no
secrets). Simulator numbers are only good for **comparing** runs on the
same machine, never as "how fast the app is". There is no Android
emulator job: GitHub's emulator has no GPU, drew glass at ~930 ms a frame
and went offline mid-run (run 41775084842, 2026-11-04).

**From real phones, with no setup (Sentry):** staging sends every
transaction and prod 20% (`tracesSampleRate`), and the screen observer
opens one per screen. Sentry adds slow frames (over the frame budget),
frozen frames (over 700 ms) and frame delay to each. In Sentry:
Insights → Mobile → Screen Rendering (or Performance → a screen
transaction), filter `environment:staging` or `prod` and the release.
Compare the release before this change with the one after, per screen
and per device. Until 2026-11-04 this was **off**: `bootstrap.dart`
called `WidgetsFlutterBinding.ensureInitialized()`, so Sentry's
`FramesTrackingIntegration` disabled itself ("incompatible binding").
It now calls `Monitoring.ensureBinding()` (Sentry's binding);
`test/core/monitoring/monitoring_binding_test.dart` keeps it that way.
Builds from before that change report no frame data.

## What we found (code review, 2026-11-03)
| Suspect | Finding |
|---|---|
| Glass under whole lists | **The likely cause** (from the code; device numbers pending). Home's exercise list, the plan's days, a plan day's exercises and the library list each sat on one glass `AppCard` (`standard`). That card is as tall as the list (the library: 23 rows, far taller than the screen), so every scroll frame re-blurred the screen behind its whole visible area (`BackdropFilter`: on Impeller a render-pass break and a screen copy) and ran the glass shader over it. Progress and history were already flat (`tall: true`) after GYM_TRACKER-12. |
| Glass per list item | Not present: rows are plain `InkWell` + `DecoratedBox`; no `BackdropFilter`/`saveLayer` per row. The active workout has glass only on the current exercise (1–2 cards). |
| Images | Bundled WebP masks and the Cloudinary library pictures (#38) come in two sizes: 160 px thumbs shown at 52 dp (≈156 px at 3×), 640 px heroes at full width (`PictureSize`). Decoded at about their shown size, so `cacheWidth` would change nothing. |
| Rebuilds on scroll | None: no `setState` or provider watch on scroll. The rest timer rebuilds only its own panel every 250 ms. |
| Picture carousel with auto-advance timer | Arrived from `main` (#38) after this review. `ExercisePicturesView` stops its timer when the app is in the background or another screen is on top (`ModalRoute.isCurrent`), and stops for good after 3 loops (a slide every 3 s); it does not pause while scrolled out of view on its own page (at most 3 loops, small). Not in the perf numbers yet: the exercise-screen flow measures it once a gym has pictures. |
| `RepaintBoundary` | `ListView` already adds one per child. |
| Bars | `GlassScaffold`'s bar re-blurs the content under it while scrolling; it is one surface and stays glass (the design). |

## What was changed
**Every glass card has no blur** (`AppCard`, `AppUi.cardSettings`, on iOS
and Android): still glass (`standard` quality, the shader's tint, rim and
highlight) but with **blur 0**. With no blur the package draws no
`BackdropFilter` for the card (`alwaysNeedsCompositing` is false and the
shader paints straight onto the canvas), so scrolling no longer re-blurs
the screen behind each card every frame. The shader still runs, so it is
cheaper, not free: measure to see how much. Bars, buttons and sheets keep
their blur; progress and history keep their flat list card (`tall: true`).

How it got there: a first commit made the cards that hold whole lists flat
(`tall: true`); the owner wanted glass, so those became glass without blur
(home's exercises, the plan's days, a plan day's exercises, the library);
then, because Settings felt heavy too, every card (owner's request).

Why the look barely changes: behind the cards is only `AppBackground`, a
soft gradient, and blurring a smooth gradient gives almost the same
gradient. Rendered with real glass in `flutter_tester` (home, library,
settings): in light no pixel of home or library moved by more than
11/255; in dark cards are a little greyer and more see-through (the blur's
saturation made them greener). Approved by the owner. Goldens don't change:
widget tests draw lite surfaces.

Tests: `test/core/ui/app_scaffold_test.dart` checks a card is glass with
`AppUi.cardSettings` (blur 0) on Android and iOS.

If device numbers show the shader itself is still too heavy on slow
Android phones, the next steps, in order: `GlassQuality.minimal` is **not**
it (it is blur only, a `BackdropFilter`); try `tall: true` (flat) on
Android only, or `GLASS_LITE` for GPU-less devices.

Also fixed here: in Arabic the arrow on Settings → "Your plan" (and every
`SettingsLinkTile`) pointed right. `Icons.chevron_right` already mirrors
itself in RTL (`matchTextDirection`), and the row also swapped to
`chevron_left` for Arabic: two flips. It now always uses `chevron_right`
(pointing left in Arabic); `settings_view_test.dart` checks both languages.

## Numbers
Only measured numbers, with the device and build mode. Times in ms; "missed"
counts frames over the 16 ms budget.

### iOS simulator (CI, debug), before the fix
Performance run 41700266401, 2026-11-03, `macos-latest`, newest
"iPhone NN" simulator, **debug** build (simulators can't run profile), on
commit `144028f` (the code before any card change). Debug numbers are
slower than a phone's and only good for comparing these two runs, which ran
one after the other on the same machine. Times in ms; "missed" = frames over
16 ms.

| flow | glass raster avg | glass raster p90 | glass missed raster | lite raster avg | lite raster p90 | lite missed raster | frames (glass / lite) |
|---|---:|---:|---:|---:|---:|---:|---:|
| home | 29.8 | 78.1 | 77 | 3.3 | 2.7 | 8 | 166 / 185 |
| plan_day | 37.7 | 82.5 | 111 | 2.0 | 2.2 | 5 | 162 / 185 |
| library | 11.4 | 36.2 | 39 | 1.8 | 2.0 | 4 | 201 / 214 |
| exercise_screen | 17.0 | 40.0 | 61 | 1.9 | 1.7 | 5 | 180 / 190 |
| progress | 1.5 | 1.4 | 3 | 3.6 | 3.7 | 9 | 191 / 189 |
| exercise_history | 12.1 | 32.8 | 42 | 3.0 | 3.2 | 9 | 184 / 185 |
| active_workout | 15.4 | 47.7 | 47 | 2.4 | 2.1 | 9 | 178 / 184 |

Build (UI thread) stayed small in both (glass build avg 0.8–4.2 ms, lite
1.0–2.4 ms): the cost is on the **raster** thread, i.e. drawing the glass.

What it shows:
- Glass costs 4–19× more average raster time than lite on every list that has a
  glass card under the list. **Progress**, whose list card was already
  flat (`tall: true`), is as cheap with glass as with lite: a list card
  without blur is the difference.
- Home and plan day, the two longest glass list cards, are the worst
  (77 and 111 of ~165 frames missed). The fix (every card without blur) covers them and every other screen.
- The exercise screen, exercise history and active workout also paid for
  glass (smaller glass cards on a scrolling page; the bar); their cards are
  now without blur too. Measure again to see what the bar still costs.

### iOS simulator (CI, debug), before vs after the fix
Performance run 41775084842, 2026-11-04, `macos-latest`, newest
"iPhone NN" simulator, **debug**. Same machine, one after the other:
"before" is glass on `main` at #47 (`155bd6d`), "after" is glass on this
PR (`d13a344`, every card without blur), "lite" is `GLASS_LITE=true`.
Average raster time in ms, and frames over 16 ms out of all frames.

| flow | before raster avg | after raster avg | lite raster avg | before missed | after missed | lite missed |
|---|---:|---:|---:|---:|---:|---:|
| home | 25.3 | 10.7 | 4.3 | 82 / 171 | 25 / 182 | 7 / 184 |
| plan_day | 25.1 | 10.0 | 1.7 | 92 / 170 | 29 / 184 | 4 / 184 |
| library | 12.9 | 2.5 | 1.7 | 40 / 203 | 3 / 212 | 4 / 214 |
| exercise_screen | 12.5 | 7.7 | 2.3 | 45 / 176 | 25 / 184 | 2 / 184 |
| progress | 1.0 | 2.5 | 1.1 | 1 / 191 | 6 / 190 | 2 / 191 |
| exercise_history | 4.3 | 7.0 | 1.1 | 6 / 184 | 20 / 183 | 0 / 185 |
| active_workout | 13.8 | 8.2 | 1.9 | 45 / 182 | 16 / 184 | 3 / 184 |

What it shows:
- Home and plan day draw ~2.4× faster and miss less than a third of the
  frames; the library is close to lite; the workout and exercise screen
  roughly halve.
- Progress and history got slower here. Progress's list card was already
  flat; history's summary card is now glass without blur instead of
  blurred glass. One run is not enough to tell noise from a real cost:
  measure again (and on a phone) before acting.
- Lite is still cheaper everywhere: what is left is the shader on the
  cards and the blurred bar.

### Android
Not measured: there is no GPU in CI's emulator (see above). Use Sentry
from the Play internal build, or a phone.

### Real phones
Not measured yet. Two ways: Sentry's screen rendering data from the
TestFlight / Play internal builds made after 2026-11-04 (above), or
`./scripts/perf.sh` on a phone plugged into a computer (with
`git checkout origin/main -- lib` and `--name before` for the old code).
Add the numbers here with the phone model, OS version and build mode.

## Move games (pose model)
Spec: `docs/designs/move_games.md` §9. Budget: the camera at ≈ 640×480, at
most 15 frames/s sent to the model (frames arriving while it is busy are
dropped); the detector works from 8 frames/s.

### App size (measured)
Release APK, prod flavor, built on Linux 2026-11-12 (`flutter build apk
--release --target-platform android-arm64 --analyze-size`), `main` at
4ed3cba vs this branch:

| | before | after | growth |
|---|---:|---:|---:|
| Universal APK | 45.7 MB | 80.8 MB | +35.1 MB (ML Kit's native library for 3 CPU types) |
| What an arm64 phone installs (from the App Bundle) | | | **+17.7 MB** (native library 10.3, models 5.8, code ≈ 1.6) |
| What a 32-bit Android phone installs | | | +13.8 MB |

The accurate model is not shipped (Gradle exclusion); only
`pose_landmark_detector_lite` and the person detector are in the assets.
iOS: not measured yet (the model bundles are not set up on iOS).

### Frames per second on phones (to measure)
On a staging build with the `move_games_debug` flag: Settings → About →
*Pose check (testing)* → *Start camera*, do 10 push-ups; note *Speed*.
Measure the cheapest Android at hand (target class: Helio G36 / Unisoc
T606, 3–4 GB) and a mid-range one. Below 8 frames/s the games will offer
the manual counter instead.

| Phone | Android | Build | Speed (frames/s) | Counted right? |
|---|---|---|---:|---|
| _to fill_ | | staging | | |
