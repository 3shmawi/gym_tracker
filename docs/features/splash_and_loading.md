# Feature: splash and loading animation

> Keep this page current — it is how a new developer or AI agent learns the feature.

## What it does
The app opens on the native splash (the static Azm mark on `#07120C`), then
a Flutter splash plays the approved logo animation (light lift → heavy lift
→ flex → static logo) while start-up runs, and opens the app as soon as both
are done. Every loading state in the app shows the same animation, looping.
Figures only: no wordmark, no text anywhere.

## User flows
1. First launch of the day: native splash → full 2.6 s animation (start-up
   work runs at the same time) → cross-fade (250 ms) into the app. If
   start-up takes longer, the static logo holds until it is done.
2. Later launches the same day: native splash → the same static logo while
   start-up runs → the app as soon as it is ready (no extra wait).
3. Reduce Motion: static logo only, no cross-fade.
4. Start-up step fails (backend, analytics, …): it is reported to
   monitoring and the app still opens.
5. A screen loads: `LoadingView` loops the animation at its size.

## Architecture
- Animation: `lib/core/ui/azm_logo_animation.dart` (`AzmLogoAnimation`,
  exported from `app_ui.dart`; `size`, `loop`, `duration` = 2.6 s,
  `progress` for a fixed frame, `semanticsLabel`, `onCompleted`) and
  `azm_logo_painter.dart` (the 1:1 port of the SVG + keyframes: one
  `CustomPainter`, one `AnimationController`, no package).
- Splash: `lib/core/splash/animated_splash.dart`, started by
  `lib/bootstrap.dart` right after monitoring; `splash_play_log.dart`
  remembers the day of the last full animation.
- Loading: `LoadingView(size: LoadingSize.inline | card | screen)` in
  `lib/core/widgets/state_views.dart`; sizes are `AppDimens.loadingInline`
  (48), `loadingCard` (96), `loadingScreen` (166, the default).
- Data sources: SharedPreferences key `splash_full_played_on`, a local date
  (`yyyy-mm-dd`), never sent anywhere.
- Routes / deep links: none.

## Analytics events
None.

## Feature flags
None.

## Tests
- Unit / widget: `test/core/ui/azm_logo_animation_test.dart` (ends on the
  static logo, loops, Reduce Motion, one label, no text, key-frame goldens),
  `test/core/ui/azm_logo_reference_test.dart` (12 frames compared with
  frames rendered from the .dc.html, `scripts/motion_reference.js`),
  `test/core/splash/animated_splash_test.dart`,
  `test/core/widgets/state_views_test.dart` (LoadingView + goldens of
  every size).
- Integration: `integration_test/app_test.dart` checks the splash opens
  the first-launch demo.

## Decisions & edge cases
- Size: `AzmLogoAnimation.nativeSplashSize` (166) puts the end frame
  exactly on the native mark (the 192-pt splash image, 5.95 px per unit on
  the 768-px export), centred on the static logo's centre (48.5, 50).
- The painted square is 112 units wide so the bars that step aside
  (right bar +16) are never clipped.
- Short version = the static logo (it already matches the native splash,
  so the hand-off has no jump).
- The play-log read times out after 300 ms (then: short) so it can never
  delay start-up.
- `AzmLogoAnimation` and `LoadingView` have a transparent background; only
  the splash screen fills `#07120C` (to match the native splash). In the
  light theme the white lines (glass edges, arms, muscle
  details) are drawn dark (`#0C1610`, same stops)
  so the figures stay visible; nothing else changes.
- The logo is never mirrored in Arabic.

## Demo & post
**Hook (first 2 seconds):** the three figures lift, lift heavier, flex, and
settle into the Azm logo.
**Scenario (what the integration test shows, with beat() pauses):**
1. App start: the animated splash plays, then the home screen.
**Caption (English):** Our splash is a tiny workout: light lift, heavy lift, flex. Then straight to your next session.
**Caption (Egyptian Arabic):** الـ splash بتاعنا تمرينة صغيرة: رفعة خفيفة، رفعة تقيلة، وبعدين استعراض عضلات. وعلى طول على تمرينتك الجاية.
**Hashtags:** #flutter #buildinpublic #gym #animation
