# Azm motion: splash animation and level figures

Source of truth for the approved animation (canvas:
https://claude.ai/artifact/26UTiBL3xuXEB8pKjCjn3L, boards `Splash` and `Levels`).
These are the exact files from that canvas: SVG shapes in a 100-unit box plus
CSS keyframes. Port them 1:1; do not redesign.

- `splash_animation.dc.html`: the approved splash animation (2.6 s).
  - 0–24 %: figure 1 presses a light bar, then drops it (bar + arms fade).
  - 26–58 %: figure 1 moves left 4.5, the right bar moves right 16; the middle
    bar turns into the intermediate figure pressing a heavy bar (slower, small
    shake at the top), then drops it. Gaps on both sides of the heavy bar: 5 units.
  - 62–92 %: figure 1 moves left 2.6, the middle bar left 14.1; the green bar
    turns into the pro bodybuilder (double-biceps, arms pump from the shoulder
    twice). Gap to the middle bar: 5 units.
  - 90–100 %: everything returns; figure 1 holds the bar overhead = the static
    logo (`assets/branding/icon_foreground.png`).
  - **The app shows no wordmark**, in the splash or in loading: the
    "Azm / عزم" text in the .dc.html file is a canvas preview only. Port the
    figures, not the text.
  - Reduce motion: static logo only.
- `level_figures.dc.html`: beginner / intermediate / pro figures
  (`lv1`, `lv2`, `lv3` symbols, 60×70 box) for the level feature.

Gradients: glass = white 60 % → 20 % → 10 %, edge = white 95 % → 15 % → 55 %,
green glass = #86EFAC → #22C55E → #15803D.

## In the app
Ported 1:1 in `lib/core/ui/azm_logo_painter.dart` (`AzmLogoAnimation`):
the splash (`lib/core/splash/`) and `LoadingView`. Nothing in the design
changed. `scripts/motion_reference.js` renders reference frames from
`splash_animation.dc.html` (Chromium) into `test/core/ui/motion_reference/`,
and `test/core/ui/azm_logo_reference_test.dart` fails if the Flutter frames
drift from them. Re-run the script whenever this file changes.
